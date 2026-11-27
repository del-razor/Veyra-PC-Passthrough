#pragma once
// OverRez: what Windows plays on the default output device, captured with WASAPI
// loopback and delivered to the recording-audio tap (RecordingAudioTap.h), so
// recordings, Instant Replay and live translation have the game's sound.

namespace veyra::sink {

// Any thread. On: the loopback stream runs and feeds the tap. Off: it closes.
// RecordingAudioTap turns it on while at least one listener is attached.
void setSystemAudioLoopback(bool on);

} // namespace veyra::sink
