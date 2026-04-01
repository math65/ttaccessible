// WebRTCEchoCanceller.h
// C wrapper around WebRTC AudioProcessing AEC3 for use from Swift.

#ifndef WEBRTC_ECHO_CANCELLER_H
#define WEBRTC_ECHO_CANCELLER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to the WebRTC AudioProcessing instance.
typedef struct WebRTCAEC* WebRTCAECRef;

/// Create a new AEC instance.
/// @param sample_rate Sample rate in Hz (must be 8000, 16000, 32000, or 48000).
/// @param channels Number of audio channels (1 or 2).
/// @return Opaque handle, or NULL on failure.
WebRTCAECRef webrtc_aec_create(int sample_rate, int channels);

/// Destroy an AEC instance and free resources.
void webrtc_aec_destroy(WebRTCAECRef aec);

/// Feed far-end (speaker/render) audio to the AEC.
/// Must be called with exactly 10ms of interleaved Int16 PCM audio.
/// @param aec The AEC handle.
/// @param data Interleaved Int16 PCM samples (10ms worth).
/// @param sample_count Number of samples per channel (e.g. 480 at 48kHz).
/// @return 0 on success, non-zero on error.
int webrtc_aec_feed_render(WebRTCAECRef aec, const int16_t* data, int sample_count);

/// Process near-end (microphone/capture) audio through the AEC.
/// Must be called with exactly 10ms of interleaved Int16 PCM audio.
/// The audio is processed in-place.
/// @param aec The AEC handle.
/// @param data Interleaved Int16 PCM samples (10ms worth), modified in-place.
/// @param sample_count Number of samples per channel (e.g. 480 at 48kHz).
/// @return 0 on success, non-zero on error.
int webrtc_aec_process_capture(WebRTCAECRef aec, int16_t* data, int sample_count);

/// Set the estimated delay in milliseconds between render and capture.
/// @param aec The AEC handle.
/// @param delay_ms Delay in milliseconds.
void webrtc_aec_set_stream_delay(WebRTCAECRef aec, int delay_ms);

#ifdef __cplusplus
}
#endif

#endif // WEBRTC_ECHO_CANCELLER_H
