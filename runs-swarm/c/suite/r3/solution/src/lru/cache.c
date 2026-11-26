/*
 * lru/cache: hash table with separate chaining over a pool of nodes that are
 * also threaded on a circular doubly linked recency list. Nodes are addressed
 * by 32-bit index so the pool can be grown with realloc; index 0 is the list
 * sentinel and doubles as the "no node" value in hash chains and the free list.
 *
 * List order: sentinel.next is the most recently used entry, sentinel.prev
 * the least recently used.
 */

#include "lru/cache.h"

#include <stdlib.h>
#include <string.h>

#define NIL 0u
#define SENTINEL 0u
#define INITIAL_NODES 1024u

struct lru_node {
    const char *key;
    const char *value;
    uint32_t hash;
    uint32_t prev;
    uint32_t next;
    uint32_t chain;     /* next node in the same hash bucket */
    uint8_t key_len;
    uint8_t value_len;
};

/* FNV-1a, followed by a final avalanche so the low bits used as the bucket
 * index depend on every input byte. */
static uint32_t hash_key(const char *key, size_t len)
{
    uint64_t h = 0xcbf29ce484222325u;
    for (size_t i = 0; i < len; i++) {
        h ^= (unsigned char)key[i];
        h *= 0x100000001b3u;
    }
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdu;
    h ^= h >> 33;
    return (uint32_t)h;
}

static void list_unlink(struct lru_node *nodes, uint32_t i)
{
    nodes[nodes[i].prev].next = nodes[i].next;
    nodes[nodes[i].next].prev = nodes[i].prev;
}

static void list_push_front(struct lru_node *nodes, uint32_t i)
{
    uint32_t first = nodes[SENTINEL].next;
    nodes[i].prev = SENTINEL;
    nodes[i].next = first;
    nodes[first].prev = i;
    nodes[SENTINEL].next = i;
}

static void list_move_front(struct lru_node *nodes, uint32_t i)
{
    if (nodes[SENTINEL].next != i) {
        list_unlink(nodes, i);
        list_push_front(nodes, i);
    }
}

/*
 * Finds `key` and returns its node index, or NIL. If `link` is non-NULL it
 * receives the address of the chain link pointing at the result (or at the
 * end of the chain on a miss), so the caller can splice the node out.
 */
static uint32_t table_find(const struct lru_cache *c, const char *key,
                           size_t len, uint32_t hash, uint32_t **link)
{
    uint32_t *p = &c->buckets[hash & c->bucket_mask];
    while (*p != NIL) {
        const struct lru_node *n = &c->nodes[*p];
        if (n->hash == hash && n->key_len == len &&
            memcmp(n->key, key, len) == 0)
            break;
        p = &c->nodes[*p].chain;
    }
    if (link)
        *link = p;
    return *p;
}

static void table_insert(struct lru_cache *c, uint32_t i)
{
    uint32_t *bucket = &c->buckets[c->nodes[i].hash & c->bucket_mask];
    c->nodes[i].chain = *bucket;
    *bucket = i;
}

static void table_remove(struct lru_cache *c, uint32_t i)
{
    const struct lru_node *n = &c->nodes[i];
    uint32_t *link;
    table_find(c, n->key, n->key_len, n->hash, &link);
    *link = n->chain;
}

/* Grows the bucket array to `count` (a power of two) and rehashes. */
static bool table_resize(struct lru_cache *c, uint32_t count)
{
    uint32_t *buckets = calloc(count, sizeof *buckets);
    if (!buckets)
        return false;
    free(c->buckets);
    c->buckets = buckets;
    c->bucket_mask = count - 1;
    for (uint32_t i = c->nodes[SENTINEL].next; i != SENTINEL; i = c->nodes[i].next)
        table_insert(c, i);
    return true;
}

static uint32_t round_up_pow2(uint32_t n)
{
    uint32_t p = 1;
    while (p < n)
        p <<= 1;
    return p;
}

/* Returns a free node slot, growing the pool (and the table with it) if
 * needed, or NIL if memory is exhausted. */
static uint32_t node_alloc(struct lru_cache *c)
{
    if (c->free_list != NIL) {
        uint32_t i = c->free_list;
        c->free_list = c->nodes[i].next;
        return i;
    }
    if (c->node_used == c->node_cap) {
        uint32_t limit = c->capacity + 1;
        uint32_t cap = c->node_cap > limit / 2 ? limit : c->node_cap * 2;
        struct lru_node *nodes = realloc(c->nodes, (size_t)cap * sizeof *nodes);
        if (!nodes)
            return NIL;
        c->nodes = nodes;
        c->node_cap = cap;
    }
    if (c->node_used > c->bucket_mask + 1 &&
        !table_resize(c, (c->bucket_mask + 1) * 2))
        return NIL;
    return c->node_used++;
}

static void node_free(struct lru_cache *c, uint32_t i)
{
    c->nodes[i].next = c->free_list;
    c->free_list = i;
}

bool lru_cache_init(struct lru_cache *c, size_t capacity)
{
    memset(c, 0, sizeof *c);
    if (capacity < 1 || capacity > LRU_CACHE_MAX_CAPACITY)
        return false;

    c->capacity = (uint32_t)capacity;
    c->node_cap = c->capacity < INITIAL_NODES ? c->capacity + 1 : INITIAL_NODES;
    c->nodes = malloc((size_t)c->node_cap * sizeof *c->nodes);
    uint32_t nbuckets = round_up_pow2(c->node_cap);
    c->buckets = calloc(nbuckets, sizeof *c->buckets);
    if (!c->nodes || !c->buckets) {
        lru_cache_destroy(c);
        return false;
    }
    c->bucket_mask = nbuckets - 1;
    c->nodes[SENTINEL].prev = SENTINEL;
    c->nodes[SENTINEL].next = SENTINEL;
    c->node_used = 1;
    return true;
}

void lru_cache_destroy(struct lru_cache *c)
{
    free(c->nodes);
    free(c->buckets);
    memset(c, 0, sizeof *c);
}

bool lru_cache_get(struct lru_cache *c, const char *key, size_t key_len,
                   const char **value, size_t *value_len)
{
    uint32_t i = table_find(c, key, key_len, hash_key(key, key_len), NULL);
    if (i == NIL)
        return false;
    list_move_front(c->nodes, i);
    *value = c->nodes[i].value;
    *value_len = c->nodes[i].value_len;
    return true;
}

bool lru_cache_set(struct lru_cache *c, const char *key, size_t key_len,
                   const char *value, size_t value_len)
{
    uint32_t hash = hash_key(key, key_len);
    uint32_t i = table_find(c, key, key_len, hash, NULL);

    if (i != NIL) {
        c->nodes[i].value = value;
        c->nodes[i].value_len = (uint8_t)value_len;
        list_move_front(c->nodes, i);
        return true;
    }

    if (c->size == c->capacity) {
        /* Full: recycle the least recently used entry's slot. */
        i = c->nodes[SENTINEL].prev;
        table_remove(c, i);
        list_unlink(c->nodes, i);
        c->size--;
    } else {
        i = node_alloc(c);
        if (i == NIL)
            return false;
    }

    struct lru_node *n = &c->nodes[i];
    n->key = key;
    n->key_len = (uint8_t)key_len;
    n->value = value;
    n->value_len = (uint8_t)value_len;
    n->hash = hash;
    table_insert(c, i);
    list_push_front(c->nodes, i);
    c->size++;
    return true;
}

bool lru_cache_del(struct lru_cache *c, const char *key, size_t key_len)
{
    uint32_t *link;
    uint32_t i = table_find(c, key, key_len, hash_key(key, key_len), &link);
    if (i == NIL)
        return false;
    *link = c->nodes[i].chain;
    list_unlink(c->nodes, i);
    node_free(c, i);
    c->size--;
    return true;
}

size_t lru_cache_size(const struct lru_cache *c)
{
    return c->size;
}
