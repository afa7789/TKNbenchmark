#include "store.h"

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct entry {
    struct entry *next;
    uint64_t hash;
    void *value;
    size_t value_len;
    size_t key_len;
    char key[];
} entry;

struct kv_store {
    pthread_rwlock_t lock;
    entry **buckets;
    size_t nbuckets; /* power of two */
    size_t count;
};

enum { INITIAL_BUCKETS = 64 };

static uint64_t hash_key(const char *key, size_t len)
{
    uint64_t h = 0xcbf29ce484222325u; /* FNV-1a */
    for (size_t i = 0; i < len; i++) {
        h ^= (unsigned char)key[i];
        h *= 0x100000001b3u;
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
            free(e->value);
            free(e);
            e = next;
        }
    }
    free(s->buckets);
    pthread_rwlock_destroy(&s->lock);
    free(s);
}

static entry **find_slot(const kv_store *s, const char *key, size_t key_len, uint64_t h)
{
    entry **pp = &s->buckets[h & (s->nbuckets - 1)];
    for (; *pp; pp = &(*pp)->next) {
        const entry *e = *pp;
        if (e->hash == h && e->key_len == key_len && memcmp(e->key, key, key_len) == 0)
            break;
    }
    return pp;
}

/* Doubles the table; failure is harmless (chains just get longer). */
static void maybe_grow(kv_store *s)
{
    if (s->count < s->nbuckets - s->nbuckets / 4 || s->nbuckets > SIZE_MAX / 2 / sizeof(entry *))
        return;
    size_t ncap = s->nbuckets * 2;
    entry **nb = calloc(ncap, sizeof *nb);
    if (!nb)
        return;
    for (size_t i = 0; i < s->nbuckets; i++) {
        entry *e = s->buckets[i];
        while (e) {
            entry *next = e->next;
            entry **slot = &nb[e->hash & (ncap - 1)];
            e->next = *slot;
            *slot = e;
            e = next;
        }
    }
    free(s->buckets);
    s->buckets = nb;
    s->nbuckets = ncap;
}

int kv_store_put(kv_store *s, const char *key, size_t key_len,
                 void *value, size_t len, bool *created)
{
    uint64_t h = hash_key(key, key_len);
    /* Allocate outside the lock; freed if the key already exists. */
    entry *fresh = malloc(sizeof *fresh + key_len + 1);
    if (!fresh)
        return ENOMEM;
    fresh->hash = h;
    fresh->key_len = key_len;
    memcpy(fresh->key, key, key_len);
    fresh->key[key_len] = '\0';
    fresh->value = value;
    fresh->value_len = len;

    void *old_value = NULL;
    pthread_rwlock_wrlock(&s->lock);
    entry **slot = find_slot(s, key, key_len, h);
    if (*slot) {
        old_value = (*slot)->value;
        (*slot)->value = value;
        (*slot)->value_len = len;
        *created = false;
    } else {
        fresh->next = NULL;
        *slot = fresh;
        fresh = NULL;
        s->count++;
        maybe_grow(s);
        *created = true;
    }
    pthread_rwlock_unlock(&s->lock);

    free(fresh);
    free(old_value);
    return 0;
}

int kv_store_get(kv_store *s, const char *key, size_t key_len,
                 void **out, size_t *out_len)
{
    uint64_t h = hash_key(key, key_len);
    int rc = 0;
    pthread_rwlock_rdlock(&s->lock);
    entry *e = *find_slot(s, key, key_len, h);
    if (!e) {
        rc = ENOENT;
    } else {
        void *copy = malloc(e->value_len ? e->value_len : 1);
        if (!copy) {
            rc = ENOMEM;
        } else {
            if (e->value_len)
                memcpy(copy, e->value, e->value_len);
            *out = copy;
            *out_len = e->value_len;
        }
    }
    pthread_rwlock_unlock(&s->lock);
    return rc;
}

int kv_store_delete(kv_store *s, const char *key, size_t key_len)
{
    uint64_t h = hash_key(key, key_len);
    pthread_rwlock_wrlock(&s->lock);
    entry **slot = find_slot(s, key, key_len, h);
    entry *e = *slot;
    if (e) {
        *slot = e->next;
        s->count--;
    }
    pthread_rwlock_unlock(&s->lock);
    if (!e)
        return ENOENT;
    free(e->value);
    free(e);
    return 0;
}

static int cmp_keys(const void *a, const void *b)
{
    const entry *x = *(const entry *const *)a;
    const entry *y = *(const entry *const *)b;
    size_t n = x->key_len < y->key_len ? x->key_len : y->key_len;
    int c = memcmp(x->key, y->key, n);
    if (c != 0)
        return c;
    return (x->key_len > y->key_len) - (x->key_len < y->key_len);
}

int kv_store_keys_json(kv_store *s, char **out, size_t *out_len)
{
    int rc = ENOMEM;
    entry **list = NULL;
    char *buf = NULL;

    pthread_rwlock_rdlock(&s->lock);
    size_t n = s->count;
    size_t total = 2; /* brackets */
    list = malloc((n ? n : 1) * sizeof *list);
    if (!list)
        goto out;
    size_t k = 0;
    for (size_t i = 0; i < s->nbuckets; i++) {
        for (entry *e = s->buckets[i]; e; e = e->next) {
            list[k++] = e;
            total += e->key_len + 3; /* quotes and comma */
        }
    }
    qsort(list, n, sizeof *list, cmp_keys);

    buf = malloc(total);
    if (!buf)
        goto out;
    size_t pos = 0;
    buf[pos++] = '[';
    for (size_t i = 0; i < n; i++) {
        if (i)
            buf[pos++] = ',';
        buf[pos++] = '"';
        memcpy(buf + pos, list[i]->key, list[i]->key_len);
        pos += list[i]->key_len;
        buf[pos++] = '"';
    }
    buf[pos++] = ']';
    *out = buf;
    *out_len = pos;
    buf = NULL;
    rc = 0;
out:
    pthread_rwlock_unlock(&s->lock);
    free(list);
    free(buf);
    return rc;
}
