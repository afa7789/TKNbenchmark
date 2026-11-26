#ifndef SUITE_HASH_H
#define SUITE_HASH_H

#include <stddef.h>
#include <stdint.h>

/* 64-bit FNV-1a with a final avalanche mix, suitable for power-of-two tables. */
static inline uint64_t hash_bytes(const char *s, size_t n)
{
    uint64_t h = 0xcbf29ce484222325u;
    for (size_t i = 0; i < n; i++) {
        h ^= (unsigned char)s[i];
        h *= 0x100000001b3u;
    }
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdu;
    h ^= h >> 33;
    return h;
}

#endif
