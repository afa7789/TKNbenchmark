#include "store.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct blob {
    atomic_size_t refs;
    size_t len;
    unsigned char data[];
};

const unsigned char *blob_data(const blob *b) { return b->data; }
size_t blob_len(const blob *b) { return b->len; }

static blob *blob_new(const void *data, size_t len)
{
    blob *b = malloc(sizeof *b + len);
    if (!b)
        return NULL;
    atomic_init(&b->refs, 1);
    b->len = len;
    if (len)
        memcpy(b->data, data, len);
    return b;
}

static void blob_retain(blob *b) { atomic_fetch_add_explicit(&b->refs, 1, memory_order_relaxed); }

void blob_release(blob *b)
{
    if (b && atomic_fetch_sub_explicit(&b->refs, 1, memory_order_acq_rel) == 1)
        free(b);
}

typedef struct entry {
    struct entry *next;
    uint64_t hash;
    blob *value;
    char key[STORE_KEY_MAX + 1];
} entry;

struct store {
    pthread_rwlock_t lock;
    entry **buckets;
    size_t nbuckets; /* always a power of two */
    size_t count;
};

#define INITIAL_BUCKETS 64

static uint64_t hash_key(const char *key)
{
    uint64_t h = 1469598103934665603ULL; /* FNV-1a */
    for (const unsigned char *p = (const unsigned char *)key; *p; p++) {
        h ^= *p;
        h *= 1099511628211ULL;
    }
    return h;
}

store *store_new(void)
{
    store *s = calloc(1, sizeof *s);
    if (!s)
        return NULL;
    s->buckets = calloc(INITIAL_BUCKETS, sizeof *s->buckets);
    if (!s->buckets || pthread_rwlock_init(&s->lock, NULL) != 0) {
        free(s->buckets);
        free(s);
        return NULL;
    }
    s->nbuckets = INITIAL_BUCKETS;
    return s;
}

void store_free(store *s)
{
    if (!s)
        return;
    for (size_t i = 0; i < s->nbuckets; i++) {
        entry *e = s->buckets[i];
        while (e) {
            entry *next = e->next;
            blob_release(e->value);
            free(e);
            e = next;
        }
    }
    free(s->buckets);
    pthread_rwlock_destroy(&s->lock);
    free(s);
}

/* Caller holds the lock. */
static entry **find_slot(const store *s, const char *key, uint64_t h)
{
    entry **pp = &s->buckets[h & (s->nbuckets - 1)];
    while (*pp && ((*pp)->hash != h || strcmp((*pp)->key, key) != 0))
        pp = &(*pp)->next;
    return pp;
}

/* Caller holds the write lock. Growth failure is not fatal: the table
 * just keeps working with longer chains. */
static void maybe_grow(store *s)
{
    if (s->count * 4 < s->nbuckets * 3)
        return;
    size_t n = s->nbuckets * 2;
    entry **nb = calloc(n, sizeof *nb);
    if (!nb)
        return;
    for (size_t i = 0; i < s->nbuckets; i++) {
        entry *e = s->buckets[i];
        while (e) {
            entry *next = e->next;
            size_t idx = e->hash & (n - 1);
            e->next = nb[idx];
            nb[idx] = e;
            e = next;
        }
    }
    free(s->buckets);
    s->buckets = nb;
    s->nbuckets = n;
}

store_put_result store_put(store *s, const char *key, const void *data, size_t len)
{
    size_t klen = strlen(key);
    if (klen > STORE_KEY_MAX)
        return STORE_NOMEM;

    blob *b = blob_new(data, len);
    if (!b)
        return STORE_NOMEM;
    uint64_t h = hash_key(key);

    pthread_rwlock_wrlock(&s->lock);
    entry **pp = find_slot(s, key, h);
    if (*pp) {
        blob *old = (*pp)->value;
        (*pp)->value = b;
        pthread_rwlock_unlock(&s->lock);
        blob_release(old);
        return STORE_OK;
    }

    entry *e = malloc(sizeof *e);
    if (!e) {
        pthread_rwlock_unlock(&s->lock);
        blob_release(b);
        return STORE_NOMEM;
    }
    e->next = NULL;
    e->hash = h;
    e->value = b;
    memcpy(e->key, key, klen + 1);
    *pp = e;
    s->count++;
    maybe_grow(s);
    pthread_rwlock_unlock(&s->lock);
    return STORE_CREATED;
}

blob *store_get(store *s, const char *key)
{
    uint64_t h = hash_key(key);
    pthread_rwlock_rdlock(&s->lock);
    entry *e = *find_slot(s, key, h);
    blob *b = NULL;
    if (e) {
        b = e->value;
        blob_retain(b);
    }
    pthread_rwlock_unlock(&s->lock);
    return b;
}

bool store_delete(store *s, const char *key)
{
    uint64_t h = hash_key(key);
    pthread_rwlock_wrlock(&s->lock);
    entry **pp = find_slot(s, key, h);
    entry *e = *pp;
    if (e) {
        *pp = e->next;
        s->count--;
    }
    pthread_rwlock_unlock(&s->lock);
    if (!e)
        return false;
    blob_release(e->value);
    free(e);
    return true;
}

static int cmp_keys(const void *a, const void *b)
{
    return strcmp(*(char *const *)a, *(char *const *)b);
}

void store_keys_free(char **keys, size_t count)
{
    if (!keys)
        return;
    for (size_t i = 0; i < count; i++)
        free(keys[i]);
    free(keys);
}

char **store_keys(store *s, size_t *count)
{
    pthread_rwlock_rdlock(&s->lock);
    size_t n = s->count;
    char **keys = malloc((n ? n : 1) * sizeof *keys);
    size_t got = 0;
    if (keys) {
        for (size_t i = 0; i < s->nbuckets; i++) {
            for (entry *e = s->buckets[i]; e; e = e->next) {
                keys[got] = strdup(e->key);
                if (!keys[got]) {
                    pthread_rwlock_unlock(&s->lock);
                    store_keys_free(keys, got);
                    return NULL;
                }
                got++;
            }
        }
    }
    pthread_rwlock_unlock(&s->lock);
    if (!keys)
        return NULL;

    qsort(keys, got, sizeof *keys, cmp_keys);
    *count = got;
    return keys;
}
