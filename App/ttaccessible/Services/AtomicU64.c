//
//  AtomicU64.c
//  ttaccessible
//

#include "AtomicU64.h"

#include <stdatomic.h>
#include <stdlib.h>

struct TTACAtomicU64 {
    _Atomic uint64_t value;
};

TTACAtomicU64 *ttac_atomic_u64_create(uint64_t initial) {
    TTACAtomicU64 *atomic = malloc(sizeof(struct TTACAtomicU64));
    if (atomic) {
        atomic_store_explicit(&atomic->value, initial, memory_order_relaxed);
    }
    return atomic;
}

void ttac_atomic_u64_destroy(TTACAtomicU64 *atomic) {
    free(atomic);
}

uint64_t ttac_atomic_u64_load(TTACAtomicU64 *atomic) {
    return atomic_load_explicit(&atomic->value, memory_order_acquire);
}

void ttac_atomic_u64_store(TTACAtomicU64 *atomic, uint64_t value) {
    atomic_store_explicit(&atomic->value, value, memory_order_release);
}
