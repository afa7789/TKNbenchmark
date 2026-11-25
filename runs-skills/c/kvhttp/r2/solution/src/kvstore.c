#include "kvstore.h"

#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

struct entry {
    struct entry *next;
    uint64_t hash;
    uint8_t *val;
    size_t vlen;
    size_t klen;
    char key[]; /* klen bytes + NUL */
};

struct kv_store {
    pthread_rwlock_t lock;
    struct entry **buckets;
    size_t nbuckets; /* power of two */
    size_t count;
};

enum { INITIAL_BUCKETS = 64 };

static uint64_t hash_key(const char *key, size_t len)
{
    /* FNV-1a, 64-bit */
    uint64_t h = 0xcbf29ce484222325u;
    for (size_t i = 0; i < len; i++) {
        h ^= (unsigned char)key[i];
        h *= 0x100000001b3u;
    }
    return h;
}

kv_store *kv_create(void)
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

void kv_destroy(kv_store *s)
{
    if (!s)
        return;
    for (size_t i = 0; i < s->nbuckets; i++) {
        struct entry *e = s->buckets[i];
        while (e) {
            struct entry *next = e->next;
            free(e->val);
            free(e);
            e = next;
        }
    }
    free(s->buckets);
    pthread_rwlock_destroy(&s->lock);
    free(s);
}

/* Returns the link pointing at the matching entry, or at the chain's NULL tail. */
static struct entry **find_slot(const kv_store *s, const char *key, size_t klen, uint64_t h)
{
    struct entry **pp = &s->buckets[h & (s->nbuckets - 1)];
    while (*pp) {
        const struct entry *e = *pp;
        if (e->hash == h && e->klen == klen && memcmp(e->key, key, klen) == 0)
            break;
        pp = &(*pp)->next;
    }
    return pp;
}

/* Double the table. Failure is harmless: chains just get longer. */
static void maybe_grow(kv_store *s)
{
    if (s->count < s->nbuckets || s->nbuckets > SIZE_MAX / 2 / sizeof *s->buckets)
        return;
    size_t ncap = s->nbuckets * 2;
    struct entry **nb = calloc(ncap, sizeof *nb);
    if (!nb)
        return;
    for (size_t i = 0; i < s->nbuckets; i++) {
        struct entry *e = s->buckets[i];
        while (e) {
            struct entry *next = e->next;
            struct entry **head = &nb[e->hash & (ncap - 1)];
            e->next = *head;
            *head = e;
            e = next;
        }
    }
    free(s->buckets);
    s->buckets = nb;
    s->nbuckets = ncap;
}

int kv_put(kv_store *s, const char *key, size_t klen, uint8_t *val, size_t vlen,
           bool *created)
{
    uint64_t h = hash_key(key, klen);

    /* Allocate the potential new entry outside the lock. */
    struct entry *fresh = malloc(sizeof *fresh + klen + 1);
    if (!fresh)
        return ENOMEM;
    fresh->next = NULL;
    fresh->hash = h;
    fresh->val = val;
    fresh->vlen = vlen;
    fresh->klen = klen;
    memcpy(fresh->key, key, klen);
    fresh->key[klen] = '\0';

    uint8_t *old_val = NULL;
    pthread_rwlock_wrlock(&s->lock);
    struct entry **slot = find_slot(s, key, klen, h);
    if (*slot) {
        old_val = (*slot)->val;
        (*slot)->val = val;
        (*slot)->vlen = vlen;
        *created = false;
    } else {
        *slot = fresh;
        fresh = NULL;
        s->count++;
        maybe_grow(s);
        *created = true;
    }
    pthread_rwlock_unlock(&s->lock);

    free(old_val);
    free(fresh);
    return 0;
}

int kv_get(kv_store *s, const char *key, size_t klen, uint8_t **out, size_t *outlen)
{
    uint64_t h = hash_key(key, klen);
    int rc = 0;

    pthread_rwlock_rdlock(&s->lock);
    const struct entry *e = *find_slot(s, key, klen, h);
    if (!e) {
        rc = ENOENT;
    } else {
        uint8_t *copy = malloc(e->vlen ? e->vlen : 1);
        if (!copy) {
            rc = ENOMEM;
        } else {
            if (e->vlen)
                memcpy(copy, e->val, e->vlen);
            *out = copy;
            *outlen = e->vlen;
        }
    }
    pthread_rwlock_unlock(&s->lock);
    return rc;
}

bool kv_delete(kv_store *s, const char *key, size_t klen)
{
    uint64_t h = hash_key(key, klen);
    struct entry *victim = NULL;

    pthread_rwlock_wrlock(&s->lock);
    struct entry **slot = find_slot(s, key, klen, h);
    if (*slot) {
        victim = *slot;
        *slot = victim->next;
        s->count--;
    }
    pthread_rwlock_unlock(&s->lock);

    if (!victim)
        return false;
    free(victim->val);
    free(victim);
    return true;
}

static int cmp_key(const void *a, const void *b)
{
    const kv_key *x = a, *y = b;
    size_t n = x->len < y->len ? x->len : y->len;
    int c = memcmp(x->data, y->data, n);
    if (c != 0)
        return c;
    return (x->len > y->len) - (x->len < y->len);
}

void kv_keys_free(kv_key *keys, size_t count)
{
    if (!keys)
        return;
    for (size_t i = 0; i < count; i++)
        free(keys[i].data);
    free(keys);
}

int kv_keys(kv_store *s, kv_key **out, size_t *count)
{
    int rc = 0;
    size_t n = 0;
    kv_key *keys = NULL;

    pthread_rwlock_rdlock(&s->lock);
    if (s->count > 0) {
        keys = calloc(s->count, sizeof *keys);
        if (!keys) {
            rc = ENOMEM;
            goto unlock;
        }
        for (size_t i = 0; i < s->nbuckets; i++) {
            for (const struct entry *e = s->buckets[i]; e; e = e->next) {
                char *k = malloc(e->klen + 1);
                if (!k) {
                    rc = ENOMEM;
                    goto unlock;
                }
                memcpy(k, e->key, e->klen + 1);
                keys[n].data = k;
                keys[n].len = e->klen;
                n++;
            }
        }
    }
unlock:
    pthread_rwlock_unlock(&s->lock);

    if (rc != 0) {
        kv_keys_free(keys, n);
        return rc;
    }
    if (n > 1)
        qsort(keys, n, sizeof *keys, cmp_key);
    *out = keys;
    *count = n;
    return 0;
}
