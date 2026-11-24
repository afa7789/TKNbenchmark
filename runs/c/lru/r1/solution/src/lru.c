/*
 * lru.c - LRU cache: chained hash table + intrusive doubly linked list.
 *
 * Entries live in a preallocated pool and refer to each other by 32-bit
 * index, which keeps nodes small and cache-friendly. Index 0 is a sentinel
 * that serves both as the list head and as the "none" marker for chains.
 */
#include "lru.h"

#include <stdlib.h>
#include <string.h>

#define NIL 0u

typedef struct {
    lru_slice key;
    lru_slice value;
    uint64_t hash;
    uint32_t prev;  /* towards most recently used */
    uint32_t next;  /* towards least recently used */
    uint32_t chain; /* next entry in the same bucket, or free-list link */
} lru_node;

struct lru_cache {
    lru_node *nodes;    /* nodes[0] is the list sentinel */
    uint32_t *buckets;  /* head index per bucket, NIL if empty */
    uint64_t mask;      /* bucket count - 1 (power of two) */
    unsigned shift;     /* 64 - log2(bucket count) */
    size_t capacity;    /* maximum number of live keys */
    size_t size;        /* current number of live keys */
    uint32_t pool_len;  /* nodes handed out so far (excluding sentinel) */
    uint32_t pool_cap;  /* nodes available (excluding sentinel) */
    uint32_t free_head; /* recycled nodes, linked through .chain */
};

static uint64_t hash_bytes(const char *p, uint32_t n)
{
    uint64_t h = 0xcbf29ce484222325ull ^ n;
    for (uint32_t i = 0; i < n; i++) {
        h ^= (unsigned char)p[i];
        h *= 0x100000001b3ull;
    }
    /* Finalizer (splitmix64) so the top bits are well mixed. */
    h ^= h >> 30;
    h *= 0xbf58476d1ce4e5b9ull;
    h ^= h >> 27;
    h *= 0x94d049bb133111ebull;
    h ^= h >> 31;
    return h;
}

static inline uint64_t bucket_of(const lru_cache *c, uint64_t hash)
{
    return (hash >> c->shift) & c->mask;
}

static inline bool slice_eq(lru_slice a, lru_slice b)
{
    return a.len == b.len && memcmp(a.ptr, b.ptr, a.len) == 0;
}

lru_cache *lru_create(size_t capacity, size_t max_entries)
{
    if (capacity == 0)
        return NULL;

    size_t live = capacity < max_entries ? capacity : max_entries;
    if (live == 0)
        live = 1;
    if (live >= UINT32_MAX - 1)
        return NULL;

    /* Load factor <= 0.5. */
    size_t nbuckets = 16;
    unsigned bits = 4;
    while (nbuckets < live * 2) {
        nbuckets <<= 1;
        bits++;
    }

    lru_cache *c = calloc(1, sizeof *c);
    if (!c)
        return NULL;
    c->nodes = malloc((live + 1) * sizeof *c->nodes);
    c->buckets = calloc(nbuckets, sizeof *c->buckets);
    if (!c->nodes || !c->buckets) {
        lru_destroy(c);
        return NULL;
    }

    c->mask = nbuckets - 1;
    c->shift = 64 - bits;
    c->capacity = capacity;
    c->pool_cap = (uint32_t)live;
    c->nodes[NIL].prev = NIL;
    c->nodes[NIL].next = NIL;
    return c;
}

void lru_destroy(lru_cache *c)
{
    if (!c)
        return;
    free(c->nodes);
    free(c->buckets);
    free(c);
}

size_t lru_size(const lru_cache *c)
{
    return c->size;
}

static inline void list_unlink(lru_cache *c, uint32_t i)
{
    lru_node *n = &c->nodes[i];
    c->nodes[n->prev].next = n->next;
    c->nodes[n->next].prev = n->prev;
}

static inline void list_push_front(lru_cache *c, uint32_t i)
{
    lru_node *head = &c->nodes[NIL];
    lru_node *n = &c->nodes[i];
    n->prev = NIL;
    n->next = head->next;
    c->nodes[head->next].prev = i;
    head->next = i;
}

/* Find the entry for `key`; if `link_out` is non-NULL it receives the address
 * of the link that points at the found entry (for unlinking). */
static uint32_t find(lru_cache *c, lru_slice key, uint64_t hash, uint32_t **link_out)
{
    uint32_t *link = &c->buckets[bucket_of(c, hash)];
    while (*link != NIL) {
        lru_node *n = &c->nodes[*link];
        if (n->hash == hash && slice_eq(n->key, key)) {
            if (link_out)
                *link_out = link;
            return *link;
        }
        link = &n->chain;
    }
    return NIL;
}

/* Remove entry `i` from its hash chain, the recency list, and return its
 * node to the free list. */
static void remove_node(lru_cache *c, uint32_t i)
{
    uint32_t *link = &c->buckets[bucket_of(c, c->nodes[i].hash)];
    while (*link != i)
        link = &c->nodes[*link].chain;
    *link = c->nodes[i].chain;

    list_unlink(c, i);
    c->nodes[i].chain = c->free_head;
    c->free_head = i;
    c->size--;
}

static uint32_t alloc_node(lru_cache *c)
{
    if (c->free_head != NIL) {
        uint32_t i = c->free_head;
        c->free_head = c->nodes[i].chain;
        return i;
    }
    if (c->pool_len < c->pool_cap)
        return ++c->pool_len;
    return NIL;
}

void lru_set(lru_cache *c, lru_slice key, lru_slice value)
{
    uint64_t hash = hash_bytes(key.ptr, key.len);
    uint32_t i = find(c, key, hash, NULL);
    if (i != NIL) {
        c->nodes[i].value = value;
        list_unlink(c, i);
        list_push_front(c, i);
        return;
    }

    /* Evicting before inserting is observably identical to inserting and
     * then evicting, and keeps the pool bounded by the capacity. */
    if (c->size >= c->capacity)
        remove_node(c, c->nodes[NIL].prev);

    i = alloc_node(c);
    if (i == NIL) {
        /* Pool exhausted: the caller underestimated max_entries. Fall back
         * to evicting the least recently used entry to make room. */
        remove_node(c, c->nodes[NIL].prev);
        i = alloc_node(c);
    }

    lru_node *n = &c->nodes[i];
    n->key = key;
    n->value = value;
    n->hash = hash;
    uint32_t *bucket = &c->buckets[bucket_of(c, hash)];
    n->chain = *bucket;
    *bucket = i;
    list_push_front(c, i);
    c->size++;
}

bool lru_get(lru_cache *c, lru_slice key, lru_slice *out)
{
    uint32_t i = find(c, key, hash_bytes(key.ptr, key.len), NULL);
    if (i == NIL)
        return false;
    *out = c->nodes[i].value;
    if (c->nodes[NIL].next != i) {
        list_unlink(c, i);
        list_push_front(c, i);
    }
    return true;
}

bool lru_del(lru_cache *c, lru_slice key)
{
    uint32_t *link;
    uint32_t i = find(c, key, hash_bytes(key.ptr, key.len), &link);
    if (i == NIL)
        return false;
    *link = c->nodes[i].chain;
    list_unlink(c, i);
    c->nodes[i].chain = c->free_head;
    c->free_head = i;
    c->size--;
    return true;
}
