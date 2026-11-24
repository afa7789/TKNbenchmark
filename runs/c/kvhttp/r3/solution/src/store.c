#include "store.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct entry {
    struct entry *next;
    uint64_t hash;
    void *val;
    size_t vlen;
    size_t klen;
    char key[]; /* NUL-terminated */
};

struct kv_store {
    struct entry **buckets;
    size_t nbuckets; /* always a power of two */
    size_t count;
};

enum { INITIAL_BUCKETS = 64 };

static uint64_t hash_key(const char *key, size_t len)
{
    uint64_t h = 0xcbf29ce484222325ULL; /* FNV-1a */
    for (size_t i = 0; i < len; i++) {
        h ^= (unsigned char)key[i];
        h *= 0x100000001b3ULL;
    }
    return h;
}

kv_store *kv_create(void)
{
    kv_store *s = malloc(sizeof *s);
    if (!s)
        return NULL;
    s->buckets = calloc(INITIAL_BUCKETS, sizeof *s->buckets);
    if (!s->buckets) {
        free(s);
        return NULL;
    }
    s->nbuckets = INITIAL_BUCKETS;
    s->count = 0;
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
    free(s);
}

static struct entry **find_slot(const kv_store *s, const char *key, size_t klen,
                                uint64_t h)
{
    struct entry **pp = &s->buckets[h & (s->nbuckets - 1)];
    for (; *pp; pp = &(*pp)->next) {
        const struct entry *e = *pp;
        if (e->hash == h && e->klen == klen && memcmp(e->key, key, klen) == 0)
            break;
    }
    return pp;
}

/* Doubles the table; failure is harmless (chains just get longer). */
static void maybe_grow(kv_store *s)
{
    if (s->count < s->nbuckets)
        return;
    size_t n = s->nbuckets * 2;
    struct entry **nb = calloc(n, sizeof *nb);
    if (!nb)
        return;
    for (size_t i = 0; i < s->nbuckets; i++) {
        struct entry *e = s->buckets[i];
        while (e) {
            struct entry *next = e->next;
            struct entry **head = &nb[e->hash & (n - 1)];
            e->next = *head;
            *head = e;
            e = next;
        }
    }
    free(s->buckets);
    s->buckets = nb;
    s->nbuckets = n;
}

static void *dup_bytes(const void *p, size_t n)
{
    void *d = malloc(n ? n : 1);
    if (d && n)
        memcpy(d, p, n);
    return d;
}

int kv_put(kv_store *s, const char *key, size_t klen,
           const void *val, size_t vlen, bool *created)
{
    uint64_t h = hash_key(key, klen);
    struct entry **pp = find_slot(s, key, klen, h);

    void *copy = dup_bytes(val, vlen);
    if (!copy)
        return -1;

    if (*pp) {
        free((*pp)->val);
        (*pp)->val = copy;
        (*pp)->vlen = vlen;
        *created = false;
        return 0;
    }

    struct entry *e = malloc(sizeof *e + klen + 1);
    if (!e) {
        free(copy);
        return -1;
    }
    e->next = NULL;
    e->hash = h;
    e->val = copy;
    e->vlen = vlen;
    e->klen = klen;
    memcpy(e->key, key, klen);
    e->key[klen] = '\0';
    *pp = e;
    s->count++;
    *created = true;
    maybe_grow(s);
    return 0;
}

bool kv_get(const kv_store *s, const char *key, size_t klen,
            const void **val, size_t *vlen)
{
    struct entry *e = *find_slot(s, key, klen, hash_key(key, klen));
    if (!e)
        return false;
    *val = e->val;
    *vlen = e->vlen;
    return true;
}

bool kv_delete(kv_store *s, const char *key, size_t klen)
{
    struct entry **pp = find_slot(s, key, klen, hash_key(key, klen));
    struct entry *e = *pp;
    if (!e)
        return false;
    *pp = e->next;
    free(e->val);
    free(e);
    s->count--;
    return true;
}

size_t kv_count(const kv_store *s)
{
    return s->count;
}

void kv_keys(const kv_store *s, const char **out)
{
    size_t n = 0;
    for (size_t i = 0; i < s->nbuckets; i++)
        for (const struct entry *e = s->buckets[i]; e; e = e->next)
            out[n++] = e->key;
}
