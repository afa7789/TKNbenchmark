#include "store.h"

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct entry {
    struct entry *next;
    uint64_t hash;
    unsigned char *data;
    size_t len;
    char key[]; /* flexible array member, NUL-terminated */
} entry;

struct kv_store {
    pthread_rwlock_t lock;
    entry **buckets;
    size_t nbuckets; /* always a power of two */
    size_t count;
};

enum { INITIAL_BUCKETS = 64 };

/* FNV-1a, 64-bit. */
static uint64_t hash_key(const char *key)
{
    uint64_t h = 0xcbf29ce484222325ULL;
    for (const unsigned char *p = (const unsigned char *)key; *p; p++) {
        h ^= *p;
        h *= 0x100000001b3ULL;
    }
    return h;
}

kv_store *kv_store_new(void)
{
    kv_store *s = calloc(1, sizeof *s);
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

void kv_store_free(kv_store *s)
{
    if (!s)
        return;
    for (size_t i = 0; i < s->nbuckets; i++) {
        entry *e = s->buckets[i];
        while (e) {
            entry *next = e->next;
            free(e->data);
            free(e);
            e = next;
        }
    }
    free(s->buckets);
    pthread_rwlock_destroy(&s->lock);
    free(s);
}

static entry **find_slot(kv_store *s, const char *key, uint64_t h)
{
    entry **pp = &s->buckets[h & (s->nbuckets - 1)];
    for (; *pp; pp = &(*pp)->next)
        if ((*pp)->hash == h && strcmp((*pp)->key, key) == 0)
            break;
    return pp;
}

/* Doubles the table; on allocation failure the table is left as is. */
static void grow(kv_store *s)
{
    size_t n = s->nbuckets * 2;
    entry **nb = calloc(n, sizeof *nb);
    if (!nb)
        return;
    for (size_t i = 0; i < s->nbuckets; i++) {
        entry *e = s->buckets[i];
        while (e) {
            entry *next = e->next;
            entry **slot = &nb[e->hash & (n - 1)];
            e->next = *slot;
            *slot = e;
            e = next;
        }
    }
    free(s->buckets);
    s->buckets = nb;
    s->nbuckets = n;
}

int kv_put(kv_store *s, const char *key, unsigned char *data, size_t len)
{
    uint64_t h = hash_key(key);
    int rc;

    pthread_rwlock_wrlock(&s->lock);
    entry **pp = find_slot(s, key, h);
    if (*pp) {
        free((*pp)->data);
        (*pp)->data = data;
        (*pp)->len = len;
        rc = 0;
    } else {
        size_t klen = strlen(key);
        entry *e = malloc(sizeof *e + klen + 1);
        if (!e) {
            free(data);
            rc = -1;
        } else {
            memcpy(e->key, key, klen + 1);
            e->hash = h;
            e->data = data;
            e->len = len;
            e->next = NULL;
            *pp = e;
            if (++s->count > s->nbuckets)
                grow(s);
            rc = 1;
        }
    }
    pthread_rwlock_unlock(&s->lock);
    return rc;
}

bool kv_get(kv_store *s, const char *key, kv_value *out)
{
    uint64_t h = hash_key(key);
    bool found = false;

    out->data = NULL;
    out->len = 0;
    pthread_rwlock_rdlock(&s->lock);
    entry *e = *find_slot(s, key, h);
    if (e) {
        found = true;
        out->len = e->len;
        if (e->len > 0) {
            out->data = malloc(e->len);
            if (out->data)
                memcpy(out->data, e->data, e->len);
        }
    }
    pthread_rwlock_unlock(&s->lock);
    return found;
}

bool kv_delete(kv_store *s, const char *key)
{
    uint64_t h = hash_key(key);
    entry *victim = NULL;

    pthread_rwlock_wrlock(&s->lock);
    entry **pp = find_slot(s, key, h);
    if (*pp) {
        victim = *pp;
        *pp = victim->next;
        s->count--;
    }
    pthread_rwlock_unlock(&s->lock);

    if (!victim)
        return false;
    free(victim->data);
    free(victim);
    return true;
}

static int cmp_str(const void *a, const void *b)
{
    return strcmp(*(char *const *)a, *(char *const *)b);
}

int kv_list(kv_store *s, kv_keys *out)
{
    out->keys = NULL;
    out->count = 0;

    pthread_rwlock_rdlock(&s->lock);
    size_t n = s->count;
    char **keys = n ? malloc(n * sizeof *keys) : NULL;
    if (n && !keys) {
        pthread_rwlock_unlock(&s->lock);
        return -1;
    }
    size_t i = 0;
    for (size_t b = 0; b < s->nbuckets; b++) {
        for (entry *e = s->buckets[b]; e; e = e->next) {
            keys[i] = strdup(e->key);
            if (!keys[i]) {
                pthread_rwlock_unlock(&s->lock);
                while (i > 0)
                    free(keys[--i]);
                free(keys);
                return -1;
            }
            i++;
        }
    }
    pthread_rwlock_unlock(&s->lock);

    qsort(keys, n, sizeof *keys, cmp_str);
    out->keys = keys;
    out->count = n;
    return 0;
}

void kv_value_free(kv_value *v)
{
    free(v->data);
    v->data = NULL;
    v->len = 0;
}

void kv_keys_free(kv_keys *k)
{
    for (size_t i = 0; i < k->count; i++)
        free(k->keys[i]);
    free(k->keys);
    k->keys = NULL;
    k->count = 0;
}
