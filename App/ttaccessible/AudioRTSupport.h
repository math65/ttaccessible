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

/// Clamp a plane pair to what the device actually has. A bad mapping must never
/// render into foreign memory, so this is applied on the render thread even
/// though Swift has already clamped the selection.
static inline void ttac_clamp_plane_pair(int devCh, int *leftPlane, int *rightPlane) {
    if (*leftPlane < 0 || *leftPlane >= devCh) *leftPlane = 0;
    if (*rightPlane >= devCh) *rightPlane = (devCh >= 2) ? 1 : -1;
    if (*rightPlane == *leftPlane) *rightPlane = -1;
    if (devCh < 2) *rightPlane = -1;
}

/// Silence every plane. Separate from the mix below so a crossfade can mix two
/// different plane pairs into the same cleared buffers.
static inline void ttac_clear_planes(float *const *planes, int devCh, int frameCount) {
    for (int ch = 0; ch < devCh; ch++) {
        memset(planes[ch], 0, (size_t)frameCount * sizeof(float));
    }
}

/// Mix the interleaved stereo Int16 pull buffer into one plane pair, with the
/// per-frame master-gain smoothing and a linear envelope running from
/// `envStart` to `envEnd` across `frameCount`.
///
/// ACCUMULATES into the planes (the caller clears them first with
/// ttac_clear_planes), so a remap can be crossfaded by calling this twice: once
/// for the outgoing pair with the envelope falling 1 -> 0, once for the incoming
/// pair with it rising 0 -> 1. Both calls start from the same `gain` and run the
/// same recurrence, so they return the same value and either may be kept.
///
/// - planes: `devCh` non-null plane pointers (caller has already null-checked).
/// - framesAvailable: frames actually pulled from the ring; the rest of the
///   buffer is left as cleared, and the gain smoothing still advances across it
///   so its state stays exact.
/// - rightPlane < 0 downmixes L/R by average onto `leftPlane` alone.
/// Returns the smoothed gain after `frameCount` frames.
static inline float ttac_mix_into_planes(float *const *planes,
                                         int devCh,
                                         const int16_t *pull,
                                         int framesAvailable,
                                         int frameCount,
                                         float gain,
                                         float gainTarget,
                                         float smoothCoeff,
                                         int leftPlane,
                                         int rightPlane,
                                         float envStart,
                                         float envEnd) {
    const float invScale = 1.0f / 32768.0f;
    ttac_clamp_plane_pair(devCh, &leftPlane, &rightPlane);

    const float envStep = (frameCount > 0) ? (envEnd - envStart) / (float)frameCount : 0.0f;
    float env = envStart;

    if (rightPlane < 0) {
        float *mono = planes[leftPlane];
        for (int f = 0; f < framesAvailable; f++) {
            gain += (gainTarget - gain) * smoothCoeff;
            const int32_t sum = ((int32_t)pull[f * 2] + (int32_t)pull[f * 2 + 1]) / 2;
            mono[f] += (float)sum * invScale * gain * env;
            env += envStep;
        }
    } else {
        float *left = planes[leftPlane];
        float *right = planes[rightPlane];
        for (int f = 0; f < framesAvailable; f++) {
            gain += (gainTarget - gain) * smoothCoeff;
            const float g = invScale * gain * env;
            left[f] += (float)pull[f * 2] * g;
            right[f] += (float)pull[f * 2 + 1] * g;
            env += envStep;
        }
    }

    // Keep the smoothing state exact across the silent tail.
    for (int f = framesAvailable; f < frameCount; f++) {
        gain += (gainTarget - gain) * smoothCoeff;
    }
    return gain;
}

/// Render the pull buffer into the device's planes at a fixed mapping: clear
/// everything, then mix the one pair at full envelope. The steady-state path,
/// used on every callback that is not mid-remap.
/// - leftPlane / rightPlane: which physical channels the mix lands on (see
///   OutputChannelSelection). Out-of-range indices fall back to 0/1.
/// Returns the smoothed gain after `frameCount` frames.
static inline float ttac_render_planes(float *const *planes,
                                       int devCh,
                                       const int16_t *pull,
                                       int framesAvailable,
                                       int frameCount,
                                       float gain,
                                       float gainTarget,
                                       float smoothCoeff,
                                       int leftPlane,
                                       int rightPlane) {
    ttac_clear_planes(planes, devCh, frameCount);
    return ttac_mix_into_planes(planes, devCh, pull, framesAvailable, frameCount,
                                gain, gainTarget, smoothCoeff,
                                leftPlane, rightPlane, 1.0f, 1.0f);
}

#endif /* AUDIO_RT_SUPPORT_H */
