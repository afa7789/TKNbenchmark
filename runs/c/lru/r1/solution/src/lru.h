/*
 * lru.h - fixed-capacity LRU cache keyed by byte strings.
 *
 * The cache does not copy keys or values: callers pass slices whose storage
 * must outlive the cache (or at least the entry referring to them).
 * All operations run in O(1) expected time.
 */
#ifndef LRU_H
#define LRU_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    const char *ptr;
    uint32_t len;
} lru_slice;

typedef struct lru_cache lru_cache;

/*
 * Create a cache holding at most `capacity` keys. `max_entries` is an upper
 * bound on the number of keys that will ever be live at once (it may be
 * smaller than `capacity` when the caller knows the workload is short);
 * storage is preallocated for min(capacity, max_entries) entries.
 * Returns NULL on allocation failure or zero capacity.
 */
lru_cache *lru_create(size_t capacity, size_t max_entries);
void lru_destroy(lru_cache *cache);

/* Insert or overwrite; the key becomes most recently used. */
void lru_set(lru_cache *cache, lru_slice key, lru_slice value);

/* On hit, store the value in *out, mark the key most recent, return true. */
bool lru_get(lru_cache *cache, lru_slice key, lru_slice *out);

/* Remove the key; return true if it was present. */
bool lru_del(lru_cache *cache, lru_slice key);

size_t lru_size(const lru_cache *cache);

#endif /* LRU_H */
