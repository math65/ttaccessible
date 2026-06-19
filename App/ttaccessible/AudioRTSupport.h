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

#endif /* AUDIO_RT_SUPPORT_H */
