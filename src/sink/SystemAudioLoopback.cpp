#include "veyra/sink/SystemAudioLoopback.h"

// OverRez: screen capture has no sound of its own, so the sound recordings, the
// Instant Replay buffer and live translation take is what Windows plays on the
// default output device (WASAPI loopback, the "desktop audio" of streaming apps).
// One shared-mode loopback stream on its own thread, open while at least one
// recording-audio listener exists (RecordingAudioTap.cpp starts and stops it).
// Packets are stamped with the recording clock at the time they were played and
// delivered as 48 kHz interleaved float in the endpoint's own speaker layout.
// While nothing plays, Windows delivers no packets, so silence is filled in to
// keep the sound continuous for the encoder.
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include "veyra/sink/AudioFormat.h"
#include "veyra/sink/RecordingAudioTap.h"
#include "veyra/Log.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstring>
#include <format>
#include <mutex>
#include <thread>
#include <vector>

extern "C" {
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
}

namespace veyra::sink {
using Microsoft::WRL::ComPtr;
namespace {

constexpr int kRate = 48000;
// Silence is filled in once Windows has delivered nothing for this long.
constexpr int64_t kSilenceAfterUs = 30000;

struct ComScope {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    ~ComScope() { if (SUCCEEDED(hr)) CoUninitialize(); }
};

// The endpoint's packet to interleaved float in its own layout.
void toFloat(const BYTE* data, UINT frames, const WavePcmFormat& format, std::vector<float>& out) {
    const unsigned channels = format.layout.channels, bytes = format.wave.wBitsPerSample / 8;
    out.resize(size_t(frames) * channels);
    if (format.floating) {
        std::memcpy(out.data(), data, out.size() * sizeof(float));
        for (auto& v : out) if (!std::isfinite(v)) v = 0.0f;
        return;
    }
    for (size_t i = 0; i < out.size(); ++i) {
        const BYTE* p = data + i * bytes;
        if (bytes == 2) { int16_t v; std::memcpy(&v, p, 2); out[i] = float(v) / 32768.0f; }
        else if (bytes == 3) { const int32_t v = int32_t(uint32_t(p[0]) << 8 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 24) >> 8; out[i] = float(v) / 8388608.0f; }
        else { int32_t v; std::memcpy(&v, p, 4); out[i] = float(double(v) / 2147483648.0); }
    }
}

struct Loopback {
    std::mutex m;
    std::condition_variable cv;
    bool wanted = false;
    uint64_t generation = 0;
    std::atomic<uint64_t> current{0};
    bool started = false;

    bool active(uint64_t gen) const { return current.load() == gen; }

    void deliver(const float* pcm, size_t frames, const AudioFormat& layout, int64_t at) {
        if (auto tap = recordingAudioSink()) tap->renderedPcm(pcm, frames, layout, at, this);
    }

    HRESULT stream(uint64_t gen) {
        ComPtr<IMMDeviceEnumerator> enumerator; ComPtr<IMMDevice> device;
        ComPtr<IAudioClient> client; ComPtr<IAudioCaptureClient> capture;
        HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&enumerator));
        if (FAILED(hr)) return hr;
        if (FAILED(hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) return hr;
        if (FAILED(hr = device->Activate(__uuidof(IAudioClient), CLSCTX_INPROC_SERVER, nullptr,
                                         reinterpret_cast<void**>(client.GetAddressOf())))) return hr;
        WAVEFORMATEX* raw = nullptr;
        if (FAILED(hr = client->GetMixFormat(&raw))) return hr;
        auto freeWave = [](WAVEFORMATEX* value) { CoTaskMemFree(value); };
        std::unique_ptr<WAVEFORMATEX, decltype(freeWave)> wave(raw, freeWave);
        WavePcmFormat format;
        if (!raw || !parseWavePcm(raw, sizeof(WAVEFORMATEX) + raw->cbSize, format)) return AUDCLNT_E_UNSUPPORTED_FORMAT;
        // Polled: loopback streams do not signal an event on every Windows version.
        if (FAILED(hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 2000000, 0, raw, nullptr))) return hr;
        if (FAILED(hr = client->GetService(IID_PPV_ARGS(&capture)))) return hr;
        const unsigned rate = raw->nSamplesPerSec;
        const AudioFormat layout = format.layout;
        SwrContext* swr = nullptr;
        struct FreeSwr { SwrContext** swr; ~FreeSwr() { if (*swr) swr_free(swr); } } freeSwr{&swr};
        if (rate != unsigned(kRate)) {
            AVChannelLayout channels{};
            if (av_channel_layout_from_mask(&channels, layout.mask) < 0) return AUDCLNT_E_UNSUPPORTED_FORMAT;
            const int made = swr_alloc_set_opts2(&swr, &channels, AV_SAMPLE_FMT_FLT, kRate, &channels, AV_SAMPLE_FMT_FLT, int(rate), 0, nullptr);
            av_channel_layout_uninit(&channels);
            if (made < 0 || !swr || swr_init(swr) < 0) return AUDCLNT_E_UNSUPPORTED_FORMAT;
        }
        // QPC packet times to the recording clock (see MicrophoneCapture.cpp).
        LARGE_INTEGER frequency{}, counter{};
        QueryPerformanceFrequency(&frequency); QueryPerformanceCounter(&counter);
        const int64_t offsetUs = recordingClockUs()
            - int64_t(double(counter.QuadPart) * 1e6 / double(std::max<LONGLONG>(1, frequency.QuadPart)));
        if (FAILED(hr = client->Start())) return hr;
        struct StopClient { IAudioClient* client; ~StopClient() { client->Stop(); } } stopClient{client.Get()};
        veyra::log::info("system-audio", std::format("loopback open rate={} channels={} mask=0x{:x} bits={} float={} resample={}",
            rate, layout.channels, layout.mask, raw->wBitsPerSample, format.floating, swr != nullptr));
        std::vector<float> pcm, resampled, silence;
        int64_t nextUs = recordingClockUs();
        auto send = [&](const float* data, UINT frames, int64_t at) {
            if (swr) {
                at -= swr_get_delay(swr, int64_t(rate)) * 1000000 / int64_t(rate);
                const int capacity = swr_get_out_samples(swr, int(frames)) + 32;
                resampled.resize(size_t(std::max(capacity, 0)) * layout.channels);
                uint8_t* out[1] = {reinterpret_cast<uint8_t*>(resampled.data())};
                const uint8_t* in[1] = {reinterpret_cast<const uint8_t*>(data)};
                const int got = swr_convert(swr, out, capacity, in, int(frames));
                if (got > 0) deliver(resampled.data(), size_t(got), layout, at);
            } else deliver(data, frames, layout, at);
        };
        while (active(gen)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            UINT next = 0;
            if (FAILED(hr = capture->GetNextPacketSize(&next))) return hr;
            bool got = false;
            while (next && active(gen)) {
                BYTE* data = nullptr; UINT frames = 0; DWORD flags = 0; UINT64 position = 0, qpc = 0;
                hr = capture->GetBuffer(&data, &frames, &flags, &position, &qpc);
                if (FAILED(hr)) return hr;
                if (hr == AUDCLNT_S_BUFFER_EMPTY) break;
                if (frames) {
                    if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) || !data) pcm.assign(size_t(frames) * layout.channels, 0.0f);
                    else toFloat(data, frames, format, pcm);
                }
                if (FAILED(hr = capture->ReleaseBuffer(frames))) return hr;
                if (frames) {
                    const int64_t at = qpc && !(flags & AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR) ? int64_t(qpc / 10) + offsetUs : nextUs;
                    send(pcm.data(), frames, at);
                    nextUs = at + int64_t(frames) * 1000000 / int64_t(rate);
                    got = true;
                }
                if (FAILED(hr = capture->GetNextPacketSize(&next))) return hr;
            }
            // Nothing is playing: fill the gap with silence up to now.
            const int64_t now = recordingClockUs();
            if (!got && now - nextUs > kSilenceAfterUs) {
                const UINT frames = UINT(std::min<int64_t>((now - nextUs) * int64_t(rate) / 1000000, int64_t(rate) / 2));
                silence.assign(size_t(frames) * layout.channels, 0.0f);
                send(silence.data(), frames, nextUs);
                nextUs += int64_t(frames) * 1000000 / int64_t(rate);
            }
        }
        return S_OK;
    }

    void run() {
        ComScope apartment;
        if (FAILED(apartment.hr)) {
            veyra::log::warn("system-audio", std::format("COM init failed hr=0x{:08X}", uint32_t(apartment.hr)));
            return;
        }
        unsigned attempt = 0;
        for (;;) {
            uint64_t gen = 0;
            {
                std::unique_lock lock(m);
                cv.wait(lock, [&] { return wanted; });
                gen = generation;
            }
            const HRESULT hr = stream(gen);
            if (FAILED(hr)) {
                // A changed or unplugged output device: open the new default again.
                veyra::log::warn("system-audio", std::format("loopback failed hr=0x{:08X} attempt={}", uint32_t(hr), attempt + 1));
                const auto backoff = std::chrono::milliseconds(std::min(attempt + 1, 5u) * 500); ++attempt;
                std::unique_lock lock(m);
                cv.wait_for(lock, backoff, [&] { return generation != gen; });
            } else {
                attempt = 0;
                veyra::log::info("system-audio", "loopback closed");
            }
        }
    }
};

Loopback& loopback() {
    // Process lifetime: the thread may still be polling at exit.
    static Loopback* instance = new Loopback;
    return *instance;
}

} // namespace

void setSystemAudioLoopback(bool on) {
    auto& l = loopback();
    {
        std::lock_guard lock(l.m);
        if (l.wanted == on) return;
        l.wanted = on;
        l.current = ++l.generation;
        if (on && !l.started) {
            l.started = true;
            std::thread([&l] { l.run(); }).detach();
        }
    }
    l.cv.notify_all();
}

} // namespace veyra::sink
