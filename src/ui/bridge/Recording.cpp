// QML bridge: Recording responsibilities.
#include "../QmlPlayerBridge_p.h"
#include "veyra/engine/MicrophoneCapture.h"

namespace veyra::ui {
// --- live recording of the processed picture --------------------------------
// The engine owns the encoder and the file; this side only starts, stops and
// shows the state. The 3 second countdown is an interface animation and runs
// before the request is sent.
QString QmlPlayerBridge::recordingDirectory() const {
    const QString chosen = impl_->prefString("recordDir");
    if (!chosen.isEmpty()) return chosen;
    const QString videos = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    return QDir(videos.isEmpty() ? QDir::homePath() : videos).filePath(QStringLiteral("Veyra"));
}
// 0 = automatic from the picture size and frame rate (LiveRecorder).
int QmlPlayerBridge::recordingBitrateMbps() const { return std::clamp(impl_->prefInt("recordBitrateMbps", 0), 0, 400); }
int QmlPlayerBridge::recordingFpsLimit() const { return std::clamp(impl_->prefInt("recordFps", 0), 0, 240); }
bool QmlPlayerBridge::recordingHevc() const { return impl_->prefBool("recordHevc", false); }
bool QmlPlayerBridge::recordingAudio() const { return impl_->prefBool("recordAudio", true); }
bool QmlPlayerBridge::recording() const { return impl_->recordingState.value("active").toBool(); }
QVariantMap QmlPlayerBridge::recordingState() const { return impl_->recordingState; }

bool QmlPlayerBridge::recordingMicrophone() const { return impl_->prefBool("recordMic", false); }
QString QmlPlayerBridge::recordingMicrophoneId() const { return impl_->prefString("recordMicDevice"); }
bool QmlPlayerBridge::recordingMicrophoneTrack() const { return impl_->prefBool("recordMicTrack", false); }
QVariantList QmlPlayerBridge::microphoneDevices() const { return impl_->microphones; }
bool QmlPlayerBridge::replayEnabled() const { return impl_->prefBool("replayEnabled", false); }
int QmlPlayerBridge::replaySeconds() const { return std::clamp(impl_->prefInt("replaySeconds", 60), 15, 600); }
QVariantMap QmlPlayerBridge::replayState() const { return impl_->replayState; }

// 设置 → 录制: what a recording and the replay buffer both follow.
engine::RecordingSettings QmlPlayerBridge::recordingOptions() const {
    engine::RecordingSettings options;
    options.directory = wideOf(recordingDirectory());
    options.bitrateMbps = uint32_t(recordingBitrateMbps());
    options.hevc = recordingHevc();
    options.fpsLimit = uint32_t(std::max(0, recordingFpsLimit()));
    options.audio = recordingAudio();
    options.microphone = recordingMicrophone();
    options.microphoneId = recordingMicrophoneId().toStdWString();
    options.microphoneTrack = recordingMicrophoneTrack();
    options.splitSeconds = uint32_t(std::clamp(impl_->prefInt("recordSplitSeconds", 0), 0, 86400));
    options.splitBytes = uint64_t(std::clamp(impl_->prefInt("recordSplitMiB", 0), 0, 1048576)) << 20;
    // NVENC tuning (设置 → 录制): two-pass and psycho-visual AQ, both off by default.
    options.multipass = uint32_t(std::clamp(impl_->prefInt("recordMultipass", 0), 0, 2));
    options.psychoAq = impl_->prefBool("recordPsychoAq", false);
    options.replaySeconds = uint32_t(replaySeconds());
    // Tests only: a small memory cap shows what the cap does.
    if (const int mb = qEnvironmentVariableIntValue("VEYRA_TEST_REPLAY_MEMORY_MB"); mb > 0) options.replayMemoryBytes = uint64_t(mb) << 20;
    return options;
}

// Every start and stop names its trigger, and a shortcut also the key the
// shortcut map was offered just before (field report 2026-11-08: recording
// toggled on and off around clicks and window activation, and the log could not
// tell a key from the 专业 button).
// (A template so the private Impl's key record is passed without naming it.)
template <class Key>
static void logRecordingRequest(const char* what, const QString& source, const QString& binding, const Key& k, const char* outcome) {
    std::string detail;
    if (source.startsWith(QStringLiteral("shortcut"))) {
        const qint64 age = k.atMs ? QDateTime::currentMSecsSinceEpoch() - k.atMs : -1;
        const QKeySequence pressed(QKeyCombination(Qt::KeyboardModifiers(k.modifiers & ~Qt::KeypadModifier), Qt::Key(k.key)));
        detail = std::format(" binding={}",binding.toStdString());
        if(age>=0&&age<=1000&&pressed==QKeySequence(binding,QKeySequence::PortableText)){
            detail += std::format(" key={} vk=0x{:X} scan=0x{:X} repeat={} receiver={} ageMs={}",
                                  binding.toStdString(),k.virtualKey,k.scanCode,k.autoRepeat,k.window.toStdString(),age);
        }else detail += " keyEvent=unobserved";
    }
    veyra::log::info("ui-record", std::format("{} source={}{} {}", what, source.isEmpty() ? std::string("unnamed") : source.toStdString(), detail, outcome));
}
void QmlPlayerBridge::startRecording(const QString& source) {
    const QString binding=source==QLatin1String("shortcut")?shortcuts().value("record").toString():QString();
    if (recording()) { logRecordingRequest("start", source, binding, impl_->lastShortcutKey, "refused=already-recording"); emit notice(tr("录制已在进行中"), true); return; }
    if (!hasSource()) { logRecordingRequest("start", source, binding, impl_->lastShortcutKey, "refused=no-source"); emit notice(tr("没有正在播放的画面，无法录制"), true); return; }
    logRecordingRequest("start", source, binding, impl_->lastShortcutKey, "requested");
    std::wstring error;
    if (!impl_->engine.requestRecording(recordingOptions(), error)) { emit notice(uiText(error), true); return; }
    // Shown at once; the poll fills in the file and the counters.
    impl_->recordingState["active"] = true;
    impl_->recordingState["failed"] = false;
    emit recordingChanged();
}
void QmlPlayerBridge::stopRecording(const QString& source) {
    const QString binding=source==QLatin1String("shortcut")?shortcuts().value("record").toString():QString();
    if (!recording()) { logRecordingRequest("stop", source, binding, impl_->lastShortcutKey, "refused=not-recording"); return; }
    logRecordingRequest("stop", source, binding, impl_->lastShortcutKey, "requested");
    impl_->engine.stopRecording();
    impl_->recordingState["active"] = false;
    emit recordingChanged();
}
void QmlPlayerBridge::toggleRecording(const QString& source) { if (recording()) stopRecording(source); else startRecording(source); }
// --- instant replay (#103) -----------------------------------------------------
// The buffer follows 设置 → 即时回放 and the recording settings; armed from
// startup, it takes frames only while something is presented.
void QmlPlayerBridge::syncReplay() {
    std::wstring error;
    const bool enabled = replayEnabled();
    if (!impl_->engine.setReplay(enabled, recordingOptions(), error)) emit notice(uiText(error), true);
    veyra::log::info("ui-replay", std::format("replay {} seconds={} microphone={}", enabled ? "on" : "off", replaySeconds(),
                                              recordingMicrophone() ? (recordingMicrophoneTrack() ? "track" : "mixed") : "off"));
    pollReplay();
}
void QmlPlayerBridge::saveReplay(const QString& source) {
    const QString binding = source.startsWith(QStringLiteral("shortcut")) ? shortcuts().value("replay").toString() : QString();
    if (!replayEnabled()) {
        logRecordingRequest("replay-save", source, binding, impl_->lastShortcutKey, "refused=off");
        emit notice(tr("即时回放未开启：设置 → 播放 → 即时回放"), true);
        return;
    }
    std::wstring error;
    if (!impl_->engine.saveReplay(wideOf(recordingDirectory()), error)) {
        logRecordingRequest("replay-save", source, binding, impl_->lastShortcutKey, "refused");
        emit notice(uiText(error), true);
        return;
    }
    logRecordingRequest("replay-save", source, binding, impl_->lastShortcutKey, "requested");
    pollReplay();
}
// Whole seconds and 10 MB steps: the state changes about once a second, not
// at the poll rate.
void QmlPlayerBridge::pollReplay() {
    const auto live = impl_->engine.replaySnapshot();
    QVariantMap state;
    state["active"] = live.active;
    state["seconds"] = int(std::floor(live.bufferedSeconds));
    state["megabytes"] = int(live.bufferedBytes / (uint64_t(10) << 20) * 10);
    state["memoryLimited"] = live.memoryLimited;
    state["saving"] = live.saving;
    state["failed"] = live.failed;
    state["error"] = live.error.empty() ? QString() : uiText(live.error);
    state["path"] = QString::fromStdWString(live.path);
    state["encoder"] = uiText(live.encoder);
    state["audio"] = live.audio;
    state["microphone"] = live.microphone;
    state["microphoneError"] = live.microphoneError.empty() ? QString() : uiText(live.microphoneError);
    state["saved"] = QVariant::fromValue(qulonglong(live.saved));
    if (state == impl_->replayState) return;
    const auto previous = impl_->replayState;
    impl_->replayState = state;
    emit replayChanged();
    if (live.saved != impl_->replaySaved) {
        impl_->replaySaved = live.saved;
        emit notice(tr("即时回放已保存：%1").arg(state.value("path").toString()), false);
    }
    const QString error = state.value("error").toString();
    if (live.failed && !error.isEmpty() && error != previous.value("error").toString()) emit notice(error, true);
}
void QmlPlayerBridge::refreshMicrophones() {
    QVariantList list;
    for (const auto& device : engine::microphoneDevices())
        list.push_back(QVariantMap{{"id", QString::fromStdWString(device.id)}, {"label", QString::fromStdWString(device.name)}});
    impl_->microphones = list;
    veyra::log::info("ui-record", std::format("microphones listed={}", list.size()));
    emit microphoneDevicesChanged();
}

void QmlPlayerBridge::chooseRecordingDirectory() {
    const QString dir = QFileDialog::getExistingDirectory(nullptr, tr("选择录制保存位置"), recordingDirectory());
    if (!dir.isEmpty()) setPreference(QStringLiteral("recordDir"), dir);
}
void QmlPlayerBridge::openRecordingDirectory() {
    const QString dir = recordingDirectory();
    QDir().mkpath(dir);
    if (!QDesktopServices::openUrl(QUrl::fromLocalFile(dir))) emit notice(tr("无法打开目录：%1").arg(dir), true);
}




void QmlPlayerBridge::restartApplication() {
    requestApplicationRestart(false);
}
void QmlPlayerBridge::restartForOverlayCompatibility() {
    requestApplicationRestart(true);
}
void QmlPlayerBridge::requestApplicationRestart(bool overlayCompatibility) {
    rememberPosition(true);
    qApp->setProperty("veyraOverlayCompatRestart", overlayCompatibility);
    // main launches the replacement only after UI/engine owners unwind.
    QCoreApplication::exit(42);
}

void QmlPlayerBridge::quit() {
    rememberPosition(true);
    if (auto* app = qobject_cast<QGuiApplication*>(QCoreApplication::instance())) app->quit();
}

void QmlPlayerBridge::openScreenCaptureDialog() { emit navigate(QStringLiteral("screen")); }
void QmlPlayerBridge::openAudioDialog() { emit navigate(QStringLiteral("audio")); }


} // namespace veyra::ui
