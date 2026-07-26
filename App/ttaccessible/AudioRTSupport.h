//
//  AudioRTSupport.h
//  ttaccessible
//
//  Real-time audio support shims. C11 memory fences for the lock-free
//  single-producer/single-consumer ring buffer used by the output render
//  engine (OutputAudioRenderEngine). The producer runs on the TeamTalk serial
//  queue; the consumer runs on the CoreAudio render thread. These fences give
//  acquire/release ordering between them without any lock — safe to call from
//  the real-time render callback (pure CPU fence, no syscall, no allocation).
//
//  macOS 14 deployment target predates Swift's Synchronization.Atomic
//  (macOS 15+), so we expose stdatomic fences to Swift instead.
//

#ifndef AUDIO_RT_SUPPORT_H
#define AUDIO_RT_SUPPORT_H

#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

/// Acquire fence: all reads after this see writes published before the
/// matching release fence on the other thread.
static inline void ttac_atomic_fence_acquire(void) {
    atomic_thread_fence(memory_order_acquire);
}

/// Release fence: publishes all prior writes to the thread that performs the
/// matching acquire fence.
static inline void ttac_atomic_fence_release(void) {
    atomic_thread_fence(memory_order_release);
}

// MARK: - Per-sample hot loops
//
// The mixer's per-frame summing and the render callback's deinterleave/convert
// loops live here in C, NOT in Swift. Unoptimized (-Onone) Swift runs these
// loops through range iterators, generic integer/float initializers and
// witness-table lookups — measured slow enough on a Debug build to miss HAL
// deadlines (audible device-level glitching) on a multi-channel interface.
// Plain C compiles to tight loops in every build configuration, so Debug and
// Release behave identically in the real-time path. Everything here is
// RT-safe: no allocation, no locks, no ObjC.

/// Zero `count` accumulator slots.
static inline void ttac_mix_clear(int32_t *acc, int count) {
    memset(acc, 0, (size_t)count * sizeof(int32_t));
}

/// Accumulate one source's interleaved PCM into the stereo Int32 accumulator
/// with per-side gains. `channels` 1 = mono (duplicated to both sides),
/// otherwise the first two interleaved channels are used. Truncation toward
/// zero matches the previous Swift `Int(Float * Float)` behavior.
///
/// `collapseToMono` folds a stereo source's two channels to their average
/// before applying the per-side gains. This is what makes panning a stereo
/// sender sound right: applying pan gains to L and R independently just fades
/// one channel's *content* out ("lopsided stereo") instead of repositioning
/// the sound. The caller sets this only for stereo sources that are panned off
/// center; a centered stereo source stays true stereo (both channels pass
/// through untouched). Mono sources ignore it.
static inline void ttac_mix_add(int32_t *acc,
                                const int16_t *src,
                                int frames,
                                int channels,
                                float leftGain,
                                float rightGain,
                                int collapseToMono) {
    if (channels == 1) {
        for (int f = 0; f < frames; f++) {
            const float s = (float)src[f];
            acc[f * 2] += (int32_t)(s * leftGain);
            acc[f * 2 + 1] += (int32_t)(s * rightGain);
        }
    } else if (collapseToMono) {
        for (int f = 0; f < frames; f++) {
            const float mono = 0.5f * ((float)src[f * channels] + (float)src[f * channels + 1]);
            acc[f * 2] += (int32_t)(mono * leftGain);
            acc[f * 2 + 1] += (int32_t)(mono * rightGain);
        }
    } else {
        for (int f = 0; f < frames; f++) {
            acc[f * 2] += (int32_t)((float)src[f * channels] * leftGain);
            acc[f * 2 + 1] += (int32_t)((float)src[f * channels + 1] * rightGain);
        }
    }
}

/// Clamp the Int32 accumulator into interleaved Int16 output.
static inline void ttac_mix_clamp(int16_t *out, const int32_t *acc, int count) {
    for (int i = 0; i < count; i++) {
        int32_t v = acc[i];
        if (v > INT16_MAX) v = INT16_MAX;
        else if (v < INT16_MIN) v = INT16_MIN;
        out[i] = (int16_t)v;
    }
}

/// Render the interleaved stereo Int16 pull buffer into the device's
/// non-interleaved Float planes with per-frame gain smoothing.
/// - planes: `devCh` non-null plane pointers (caller has already null-checked).
/// - framesAvailable: frames actually pulled from the ring; the remainder up
///   to `frameCount` is filled with silence (gain smoothing still advances).
/// - devCh == 1 downmixes L/R by average; devCh >= 2 maps L->0, R->1 and
///   silences the extra channels.
/// Returns the smoothed gain after `frameCount` frames.
static inline float ttac_render_planes(float *const *planes,
                                       int devCh,
                                       const int16_t *pull,
                                       int framesAvailable,
                                       int frameCount,
                                       float gain,
                                       float gainTarget,
                                       float smoothCoeff) {
    const float invScale = 1.0f / 32768.0f;
    for (int ch = 2; ch < devCh; ch++) {
        memset(planes[ch], 0, (size_t)frameCount * sizeof(float));
    }
    if (devCh == 1) {
        float *mono = planes[0];
        for (int f = 0; f < framesAvailable; f++) {
            gain += (gainTarget - gain) * smoothCoeff;
            const int32_t sum = ((int32_t)pull[f * 2] + (int32_t)pull[f * 2 + 1]) / 2;
            mono[f] = (float)sum * invScale * gain;
        }
        if (framesAvailable < frameCount) {
            memset(mono + framesAvailable, 0,
                   (size_t)(frameCount - framesAvailable) * sizeof(float));
        }
    } else {
        float *left = planes[0];
        float *right = planes[1];
        for (int f = 0; f < framesAvailable; f++) {
            gain += (gainTarget - gain) * smoothCoeff;
            const float g = invScale * gain;
            left[f] = (float)pull[f * 2] * g;
            right[f] = (float)pull[f * 2 + 1] * g;
        }
        if (framesAvailable < frameCount) {
            const size_t tail = (size_t)(frameCount - framesAvailable) * sizeof(float);
            memset(left + framesAvailable, 0, tail);
            memset(right + framesAvailable, 0, tail);
        }
    }
    // Keep the smoothing state exact across the silent tail.
    for (int f = framesAvailable; f < frameCount; f++) {
        gain += (gainTarget - gain) * smoothCoeff;
    }
    return gain;
}

#endif /* AUDIO_RT_SUPPORT_H */
