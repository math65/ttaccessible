//
//  AtomicU64.h
//  ttaccessible
//
//  Minimal C11 atomic UInt64 so the device-stream ring can publish its write
//  cursor from the real-time audio thread with release/acquire ordering and no
//  lock. Swift's Synchronization.Atomic requires macOS 15; the deployment target
//  here is 12, hence this thin shim (same bridging pattern as OpusShim).
//

#ifndef TTAC_ATOMIC_U64_H
#define TTAC_ATOMIC_U64_H

#include <stdint.h>

typedef struct TTACAtomicU64 TTACAtomicU64;

/// Allocate an atomic initialised to `initial`. Heap-allocated so its address is
/// stable for the lifetime of the ring; caller owns it and must destroy it.
TTACAtomicU64 *ttac_atomic_u64_create(uint64_t initial);
void ttac_atomic_u64_destroy(TTACAtomicU64 *atomic);

/// Acquire-load — pairs with the release-store to observe the producer's writes.
uint64_t ttac_atomic_u64_load(TTACAtomicU64 *atomic);
/// Release-store — publishes the non-atomic buffer writes made before it.
void ttac_atomic_u64_store(TTACAtomicU64 *atomic, uint64_t value);

#endif /* TTAC_ATOMIC_U64_H */
