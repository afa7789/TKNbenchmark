#include "lru.h"

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define NIL UINT32_MAX
#define INITIAL_POOL 64u

typedef struct {
    lru_str key;
    lru_str value;
    uint64_t hash;
    uint32_t prev, next; /* recency list; head = most recently used */
    uint32_t chain;      /* next node in the same bucket, or free-list link */
} node;

struct lru_cache {
    node *nodes;
    uint32_t *buckets;
    size_t bucket_mask;
    size_t capacity;
    size_t size;
    uint32_t pool_len; /* nodes ever handed out from the pool */
    uint32_t pool_cap; /* nodes allocated */
    uint32_t free_list;
    uint32_t head, tail;
};

static uint64_t hash_bytes(const char *p, size_t n)
{
    uint64_t h = 0xcbf29ce484222325u; /* FNV-1a */
    for (size_t i = 0; i < n; i++) {
        h ^= (unsigned char)p[i];
        h *= 0x100000001b3u;
    }
    /* Final avalanche so the low bits used for bucketing are well mixed. */
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdu;
    h ^= h >> 33;
    return h;
}

static size_t bucket_count_for(size_t nodes)
{
    size_t n = 1;
    while (n < nodes * 2)
        n <<= 1;
    return n;
}

static int rebuild_buckets(lru_cache *c, size_t nbuckets)
{
    uint32_t *b = malloc(nbuckets * sizeof *b);
    if (!b)
        return ENOMEM;
    for (size_t i = 0; i < nbuckets; i++)
        b[i] = NIL;
    for (uint32_t i = c->head; i != NIL; i = c->nodes[i].next) {
        uint32_t *slot = &b[c->nodes[i].hash & (nbuckets - 1)];
        c->nodes[i].chain = *slot;
        *slot = i;
    }
    free(c->buckets);
    c->buckets = b;
    c->bucket_mask = nbuckets - 1;
    return 0;
}

/* Grow the node pool (never beyond capacity), rehashing as needed. */
static int grow(lru_cache *c)
{
    size_t ncap = (size_t)c->pool_cap * 2;
    if (ncap > c->capacity)
        ncap = c->capacity;
    node *n = realloc(c->nodes, ncap * sizeof *n);
    if (!n)
        return ENOMEM;
    c->nodes = n;
    size_t nbuckets = bucket_count_for(ncap);
    if (nbuckets > c->bucket_mask + 1) {
        int err = rebuild_buckets(c, nbuckets);
        if (err)
            return err; /* larger pool with old buckets is still valid */
    }
    c->pool_cap = (uint32_t)ncap;
    return 0;
}

lru_cache *lru_create(size_t capacity)
{
    if (capacity == 0 || capacity >= NIL)
        return NULL;

    lru_cache *c = malloc(sizeof *c);
    if (!c)
        return NULL;
    size_t pool = capacity < INITIAL_POOL ? capacity : INITIAL_POOL;
    size_t nbuckets = bucket_count_for(pool);
    c->nodes = malloc(pool * sizeof *c->nodes);
    c->buckets = malloc(nbuckets * sizeof *c->buckets);
    if (!c->nodes || !c->buckets) {
        lru_destroy(c);
        return NULL;
    }
    for (size_t i = 0; i < nbuckets; i++)
        c->buckets[i] = NIL;

    c->bucket_mask = nbuckets - 1;
    c->capacity = capacity;
    c->size = 0;
    c->pool_len = 0;
    c->pool_cap = (uint32_t)pool;
    c->free_list = NIL;
    c->head = c->tail = NIL;
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

static inline bool key_eq(const node *n, uint64_t hash, lru_str key)
{
    return n->hash == hash && n->key.len == key.len &&
           memcmp(n->key.data, key.data, key.len) == 0;
}

/* Return the link that refers to the node holding `key` (a bucket slot or a
 * predecessor's chain field); it holds NIL if the key is absent. */
static uint32_t *find_link(lru_cache *c, uint64_t hash, lru_str key)
{
    uint32_t *link = &c->buckets[hash & c->bucket_mask];
    while (*link != NIL && !key_eq(&c->nodes[*link], hash, key))
        link = &c->nodes[*link].chain;
    return link;
}

static void list_unlink(lru_cache *c, uint32_t i)
{
    node *n = &c->nodes[i];
    if (n->prev != NIL)
        c->nodes[n->prev].next = n->next;
    else
        c->head = n->next;
    if (n->next != NIL)
        c->nodes[n->next].prev = n->prev;
    else
        c->tail = n->prev;
}

static void list_push_front(lru_cache *c, uint32_t i)
{
    node *n = &c->nodes[i];
    n->prev = NIL;
    n->next = c->head;
    if (c->head != NIL)
        c->nodes[c->head].prev = i;
    else
        c->tail = i;
    c->head = i;
}

static void touch(lru_cache *c, uint32_t i)
{
    if (c->head == i)
        return;
    list_unlink(c, i);
    list_push_front(c, i);
}

/* Detach node `i`, reached via `link`, from its bucket and the recency list,
 * and return it to the free list. */
static void remove_node(lru_cache *c, uint32_t *link, uint32_t i)
{
    *link = c->nodes[i].chain;
    list_unlink(c, i);
    c->nodes[i].chain = c->free_list;
    c->free_list = i;
    c->size--;
}

static void evict_lru(lru_cache *c)
{
    uint32_t victim = c->tail;
    uint32_t *link = &c->buckets[c->nodes[victim].hash & c->bucket_mask];
    while (*link != victim)
        link = &c->nodes[*link].chain;
    remove_node(c, link, victim);
}

int lru_set(lru_cache *c, lru_str key, lru_str value)
{
    uint64_t hash = hash_bytes(key.data, key.len);
    uint32_t *link = find_link(c, hash, key);
    if (*link != NIL) {
        c->nodes[*link].value = value;
        touch(c, *link);
        return 0;
    }

    uint32_t i;
    if (c->size == c->capacity) {
        evict_lru(c);
        i = c->free_list;
        c->free_list = c->nodes[i].chain;
    } else if (c->free_list != NIL) {
        i = c->free_list;
        c->free_list = c->nodes[i].chain;
    } else {
        if (c->pool_len == c->pool_cap) {
            int err = grow(c);
            if (err)
                return err;
        }
        i = c->pool_len++;
    }

    node *n = &c->nodes[i];
    n->key = key;
    n->value = value;
    n->hash = hash;
    /* Eviction or rehashing may have changed the bucket; look it up afresh. */
    uint32_t *bucket = &c->buckets[hash & c->bucket_mask];
    n->chain = *bucket;
    *bucket = i;
    list_push_front(c, i);
    c->size++;
    return 0;
}

bool lru_get(lru_cache *c, lru_str key, lru_str *out)
{
    uint64_t hash = hash_bytes(key.data, key.len);
    uint32_t i = *find_link(c, hash, key);
    if (i == NIL)
        return false;
    touch(c, i);
    *out = c->nodes[i].value;
    return true;
}

bool lru_del(lru_cache *c, lru_str key)
{
    uint64_t hash = hash_bytes(key.data, key.len);
    uint32_t *link = find_link(c, hash, key);
    if (*link == NIL)
        return false;
    remove_node(c, link, *link);
    return true;
}
