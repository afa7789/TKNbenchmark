/*
 * lru/cache: a fixed-capacity LRU map from byte-string keys to byte-string
 * values, with O(1) expected time per operation.
 *
 * The cache does not copy keys or values: it stores the caller's pointers,
 * so the bytes they point to must stay valid and unchanged for as long as
 * the cache may refer to them (until the entry is overwritten, deleted or
 * evicted, or the cache is destroyed).
 */
#ifndef LRU_CACHE_H
#define LRU_CACHE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Longest key or value the cache accepts, in bytes. */
#define LRU_CACHE_MAX_LEN 255u

/* Largest supported capacity. */
#define LRU_CACHE_MAX_CAPACITY (UINT32_MAX / 4u)

struct lru_node;

struct lru_cache {
    struct lru_node *nodes;   /* nodes[0] is the sentinel of the recency list */
    uint32_t *buckets;        /* hash chains of node indices; 0 ends a chain  */
    uint32_t bucket_mask;     /* bucket count - 1 (a power of two)            */
    uint32_t node_cap;        /* allocated slots in nodes, sentinel included  */
    uint32_t node_used;       /* slots ever handed out, sentinel included     */
    uint32_t free_list;       /* recycled slots linked by next; 0 if none     */
    uint32_t size;            /* live entries                                 */
    uint32_t capacity;        /* maximum live entries                         */
};

/*
 * Initialises an empty cache holding at most `capacity` entries
 * (1 ≤ capacity ≤ LRU_CACHE_MAX_CAPACITY). Returns false if the capacity
 * is out of range or memory is exhausted.
 */
bool lru_cache_init(struct lru_cache *cache, size_t capacity);

/* Releases all memory owned by the cache. */
void lru_cache_destroy(struct lru_cache *cache);

/*
 * Looks up `key`. On a hit, marks it most recently used, stores its value
 * in *value / *value_len and returns true; otherwise returns false.
 */
bool lru_cache_get(struct lru_cache *cache, const char *key, size_t key_len,
                   const char **value, size_t *value_len);

/*
 * Inserts or overwrites `key`, making it the most recently used entry and
 * evicting the least recently used one if the cache would exceed its
 * capacity. Both lengths must be at most LRU_CACHE_MAX_LEN. Returns false
 * only if memory is exhausted, in which case the cache is unchanged.
 */
bool lru_cache_set(struct lru_cache *cache, const char *key, size_t key_len,
                   const char *value, size_t value_len);

/* Removes `key`. Returns whether it was present. */
bool lru_cache_del(struct lru_cache *cache, const char *key, size_t key_len);

/* Returns the number of entries held. */
size_t lru_cache_size(const struct lru_cache *cache);

#endif
