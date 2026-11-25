#ifndef LRU_LRU_H
#define LRU_LRU_H

#include <stdbool.h>
#include <stddef.h>

/*
 * Fixed-capacity LRU cache mapping byte-string keys to byte-string values.
 *
 * The cache does not copy keys or values: it stores views into memory owned
 * by the caller, which must stay valid and unchanged for as long as the
 * cache may reference them (until the entry is overwritten, deleted, evicted
 * or the cache is destroyed).
 *
 * All operations run in O(1) expected time.
 */

typedef struct lru_cache lru_cache;

typedef struct {
    const char *data;
    size_t len;
} lru_str;

/*
 * Create a cache holding at most `capacity` keys (1 <= capacity < 2^32 - 1).
 * Storage grows on demand. Returns NULL on invalid capacity or allocation
 * failure.
 */
lru_cache *lru_create(size_t capacity);
void lru_destroy(lru_cache *c);

/* Insert or overwrite; the key becomes most recently used. Evicts the least
 * recently used key if the cache would exceed its capacity. Returns 0, or
 * ENOMEM if storage could not grow (the cache is left unchanged). */
int lru_set(lru_cache *c, lru_str key, lru_str value);

/* On hit, store the value in *out, mark the key most recently used and
 * return true. */
bool lru_get(lru_cache *c, lru_str key, lru_str *out);

/* Remove the key; returns true if it was present. */
bool lru_del(lru_cache *c, lru_str key);

size_t lru_size(const lru_cache *c);

#endif
