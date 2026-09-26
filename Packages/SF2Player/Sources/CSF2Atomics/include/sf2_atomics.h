#ifndef SF2_ATOMICS_H
#define SF2_ATOMICS_H
#include <stdint.h>

// Plain C11/GCC atomic builtins so Swift can do acquire/release on shared words from the
// real-time audio thread without locks, allocation or runtime calls (iOS 16: no Synchronization).
static inline int64_t sf2_atomic_load_i64(const int64_t *p) { return __atomic_load_n(p, __ATOMIC_ACQUIRE); }
static inline void sf2_atomic_store_i64(int64_t *p, int64_t v) { __atomic_store_n(p, v, __ATOMIC_RELEASE); }
static inline uint64_t sf2_atomic_load_u64(const uint64_t *p) { return __atomic_load_n(p, __ATOMIC_ACQUIRE); }
static inline void sf2_atomic_store_u64(uint64_t *p, uint64_t v) { __atomic_store_n(p, v, __ATOMIC_RELEASE); }

#endif
