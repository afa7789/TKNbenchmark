#include "kv_store.h"

#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct kv_value {
    atomic_size_t refs;
    size_t len;
    unsigned char data[];
};

kv_value *kv_value_new(const void *data, size_t len)
{
    if (len > SIZE_MAX - sizeof(kv_value))
        return NULL;
    kv_value *v = malloc(sizeof *v + len);
    if (!v)
        return NULL;
    atomic_init(&v->refs, 1);
    v->len = len;
    if (len)
        memcpy(v->data, data, len);
    return v;
}

void kv_value_retain(kv_value *v)
{
    atomic_fetch_add_explicit(&v->refs, 1, memory_order_relaxed);
}

void kv_value_release(kv_value *v)
{
    if (v && atomic_fetch_sub_explicit(&v->refs, 1, memory_order_acq_rel) == 1)
        free(v);
}

const unsigned char *kv_value_data(const kv_value *v) { return v->data; }
size_t kv_value_len(const kv_value *v) { return v->len; }

typedef struct entry {
    struct entry *next;
    uint64_t hash;
    kv_value *value;
    size_t klen;
    char key[KV_KEY_MAX + 1];
} entry;

struct kv_store {
    pthread_rwlock_t lock;
    entry **buckets;
    size_t nbuckets; /* power of two */
    size_t count;
};

#define INITIAL_BUCKETS 64

static uint64_t hash_key(const char *key, size_t len)
{
    uint64_t h = 1469598103934665603ULL; /* FNV-1a */
    for (size_t i = 0; i < len; i++) {
        h ^= (unsigned char)key[i];
        h *= 1099511628211ULL;
    }
    return h;
}

bool kv_key_valid(const char *key, size_t len)
{
    if (len == 0 || len > KV_KEY_MAX)
        return false;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)key[i];
        bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                  (c >= '0' && c <= '9') || c == '_' || c == '-';
        if (!ok)
            return false;
    }
    return true;
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
            kv_value_release(e->value);
            free(e);
            e = next;
        }
    }
    free(s->buckets);
    pthread_rwlock_destroy(&s->lock);
    free(s);
}

static entry **find_slot(kv_store *s, const char *key, size_t klen, uint64_t h)
{
    entry **pp = &s->buckets[h & (s->nbuckets - 1)];
    for (; *pp; pp = &(*pp)->next) {
        entry *e = *pp;
        if (e->hash == h && e->klen == klen && memcmp(e->key, key, klen) == 0)
            break;
    }
    return pp;
}

/* Doubles the table; failure is harmless (chains just get longer). */
static void maybe_grow(kv_store *s)
{
    if (s->count < s->nbuckets || s->nbuckets > SIZE_MAX / 2 / sizeof(entry *))
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

int kv_store_put(kv_store *s, const char *key, size_t klen, kv_value *v, bool *created)
{
    if (klen > KV_KEY_MAX)
        return EINVAL;
    uint64_t h = hash_key(key, klen);
    kv_value *old = NULL;
    int rc = 0;

    pthread_rwlock_wrlock(&s->lock);
    entry **slot = find_slot(s, key, klen, h);
    if (*slot) {
        old = (*slot)->value;
        (*slot)->value = v;
        *created = false;
    } else {
        entry *e = malloc(sizeof *e);
        if (!e) {
            rc = ENOMEM;
        } else {
            e->next = NULL;
            e->hash = h;
            e->value = v;
            e->klen = klen;
            memcpy(e->key, key, klen);
            e->key[klen] = '\0';
            *slot = e;
            s->count++;
            *created = true;
            maybe_grow(s);
        }
    }
    pthread_rwlock_unlock(&s->lock);

    kv_value_release(old);
    return rc;
}

kv_value *kv_store_get(kv_store *s, const char *key, size_t klen)
{
    uint64_t h = hash_key(key, klen);
    kv_value *v = NULL;

    pthread_rwlock_rdlock(&s->lock);
    entry *e = *find_slot(s, key, klen, h);
    if (e) {
        v = e->value;
        kv_value_retain(v);
    }
    pthread_rwlock_unlock(&s->lock);
    return v;
}

bool kv_store_delete(kv_store *s, const char *key, size_t klen)
{
    uint64_t h = hash_key(key, klen);
    entry *victim = NULL;

    pthread_rwlock_wrlock(&s->lock);
    entry **slot = find_slot(s, key, klen, h);
    if (*slot) {
        victim = *slot;
        *slot = victim->next;
        s->count--;
    }
    pthread_rwlock_unlock(&s->lock);

    if (!victim)
        return false;
    kv_value_release(victim->value);
    free(victim);
    return true;
}

void kv_keys_free(char **keys, size_t count)
{
    if (!keys)
        return;
    for (size_t i = 0; i < count; i++)
        free(keys[i]);
    free(keys);
}

static int cmp_str(const void *a, const void *b)
{
    return strcmp(*(char *const *)a, *(char *const *)b);
}

int kv_store_keys(kv_store *s, char ***out, size_t *count)
{
    char **keys = NULL;
    size_t n = 0;
    int rc = 0;

    pthread_rwlock_rdlock(&s->lock);
    if (s->count) {
        keys = calloc(s->count, sizeof *keys);
        if (!keys) {
            rc = ENOMEM;
        } else {
            for (size_t i = 0; i < s->nbuckets && !rc; i++) {
                for (entry *e = s->buckets[i]; e; e = e->next) {
                    keys[n] = malloc(e->klen + 1);
                    if (!keys[n]) {
                        rc = ENOMEM;
                        break;
                    }
                    memcpy(keys[n], e->key, e->klen + 1);
                    n++;
                }
            }
        }
    }
    pthread_rwlock_unlock(&s->lock);

    if (rc) {
        kv_keys_free(keys, n);
        return rc;
    }
    if (n > 1)
        qsort(keys, n, sizeof *keys, cmp_str);
    *out = keys;
    *count = n;
    return 0;
}
