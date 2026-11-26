/*
 * `app lru`: LRU cache simulator (see SPEC.md, section "lru").
 *
 * The whole of standard input is read into one buffer that stays alive (and
 * unmodified) until the end, so cache entries simply point at their key and
 * value bytes inside it: no per-entry string allocation is ever needed.
 *
 * Entries live in a growable pool and are addressed by 32-bit index. Each
 * entry sits on two intrusive lists:
 *   - a doubly linked recency list (head = most recent, tail = least recent);
 *   - a singly linked hash-bucket chain.
 * Every command is therefore O(1) expected time.
 */
#include "lru.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NIL UINT32_MAX

/* ---------------------------------------------------------------- input */

struct slice {
    const char *ptr;
    size_t len;
};

static bool slice_eq(struct slice a, struct slice b)
{
    return a.len == b.len && memcmp(a.ptr, b.ptr, a.len) == 0;
}

static bool slice_is(struct slice s, const char *lit)
{
    size_t n = strlen(lit);
    return s.len == n && memcmp(s.ptr, lit, n) == 0;
}

/* Reads all of `in` into a heap buffer. Returns NULL on allocation/IO error. */
static char *read_all(FILE *in, size_t *out_len)
{
    size_t cap = 1 << 20, len = 0;
    char *buf = malloc(cap);
    if (buf == NULL)
        return NULL;

    for (;;) {
        if (len == cap) {
            size_t ncap = cap * 2;
            char *nbuf = realloc(buf, ncap);
            if (nbuf == NULL) {
                free(buf);
                return NULL;
            }
            buf = nbuf;
            cap = ncap;
        }
        size_t n = fread(buf + len, 1, cap - len, in);
        len += n;
        if (n == 0) {
            if (ferror(in)) {
                free(buf);
                return NULL;
            }
            break;
        }
    }
    *out_len = len;
    return buf;
}

/* Splits the next line off [*cur, end); strips a trailing '\r'. */
static bool next_line(const char **cur, const char *end, struct slice *line)
{
    const char *p = *cur;
    if (p >= end)
        return false;

    const char *nl = memchr(p, '\n', (size_t)(end - p));
    const char *stop = nl != NULL ? nl : end;
    *cur = nl != NULL ? nl + 1 : end;

    if (stop > p && stop[-1] == '\r')
        stop--;
    line->ptr = p;
    line->len = (size_t)(stop - p);
    return true;
}

/* Splits up to `max` space-separated tokens from `line`; returns the count,
 * or max + 1 if there are more tokens than that. */
static size_t tokenize(struct slice line, struct slice *tok, size_t max)
{
    const char *p = line.ptr, *end = line.ptr + line.len;
    size_t n = 0;

    for (;;) {
        while (p < end && *p == ' ')
            p++;
        if (p == end)
            return n;
        if (n == max)
            return max + 1;
        const char *start = p;
        while (p < end && *p != ' ')
            p++;
        tok[n].ptr = start;
        tok[n].len = (size_t)(p - start);
        n++;
    }
}

/* Parses a decimal capacity in [1, 1000000] surrounded by optional blanks. */
static bool parse_capacity(struct slice s, uint32_t *out)
{
    const char *p = s.ptr, *end = s.ptr + s.len;
    while (p < end && (*p == ' ' || *p == '\t'))
        p++;
    while (end > p && (end[-1] == ' ' || end[-1] == '\t'))
        end--;
    if (p < end && *p == '+')
        p++;
    if (p == end)
        return false;

    uint64_t v = 0;
    for (; p < end; p++) {
        if (*p < '0' || *p > '9')
            return false;
        v = v * 10 + (uint64_t)(*p - '0');
        if (v > 1000000)
            return false;
    }
    if (v == 0)
        return false;
    *out = (uint32_t)v;
    return true;
}

/* --------------------------------------------------------------- output */

struct outbuf {
    char *buf;
    size_t len, cap;
    FILE *out;
};

static void out_flush(struct outbuf *o)
{
    if (o->len > 0) {
        fwrite(o->buf, 1, o->len, o->out);
        o->len = 0;
    }
}

static void out_write(struct outbuf *o, const char *s, size_t n)
{
    if (o->cap - o->len < n + 1) {
        out_flush(o);
        if (o->cap < n + 1) {
            fwrite(s, 1, n, o->out);
            fputc('\n', o->out);
            return;
        }
    }
    memcpy(o->buf + o->len, s, n);
    o->len += n;
    o->buf[o->len++] = '\n';
}

static void out_uint(struct outbuf *o, uint32_t v)
{
    char tmp[16];
    size_t i = sizeof tmp;
    do {
        tmp[--i] = (char)('0' + v % 10);
        v /= 10;
    } while (v != 0);
    out_write(o, tmp + i, sizeof tmp - i);
}

/* ---------------------------------------------------------------- cache */

struct entry {
    struct slice key;
    struct slice value;
    uint32_t hash;
    uint32_t prev, next;  /* recency list; prev is toward the head (MRU) */
    uint32_t chain;       /* next entry in the same hash bucket, or free list */
};

struct cache {
    struct entry *pool;
    uint32_t pool_len, pool_cap;
    uint32_t free_head;

    uint32_t *buckets;
    uint32_t mask;         /* bucket count - 1; bucket count is a power of 2 */

    uint32_t head, tail;
    uint32_t size, capacity;
};

static uint32_t hash_bytes(struct slice s)
{
    /* FNV-1a, then a murmur3 finalizer to spread the low bits. */
    uint64_t h = 0xcbf29ce484222325u;
    for (size_t i = 0; i < s.len; i++) {
        h ^= (unsigned char)s.ptr[i];
        h *= 0x100000001b3u;
    }
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdu;
    h ^= h >> 33;
    h *= 0xc4ceb9fe1a85ec53u;
    h ^= h >> 33;
    return (uint32_t)h;
}

static bool cache_init(struct cache *c, uint32_t capacity)
{
    *c = (struct cache){
        .free_head = NIL, .head = NIL, .tail = NIL, .capacity = capacity,
    };
    uint32_t nbuckets = 1024;
    c->buckets = malloc(nbuckets * sizeof *c->buckets);
    if (c->buckets == NULL)
        return false;
    memset(c->buckets, 0xff, nbuckets * sizeof *c->buckets);
    c->mask = nbuckets - 1;
    return true;
}

static void cache_free(struct cache *c)
{
    free(c->pool);
    free(c->buckets);
}

/* Doubles the bucket array and redistributes the live entries. */
static bool cache_rehash(struct cache *c)
{
    uint32_t nbuckets = (c->mask + 1) * 2;
    uint32_t *nb = malloc((size_t)nbuckets * sizeof *nb);
    if (nb == NULL)
        return false;
    memset(nb, 0xff, (size_t)nbuckets * sizeof *nb);

    uint32_t nmask = nbuckets - 1;
    for (uint32_t i = c->head; i != NIL; i = c->pool[i].next) {
        uint32_t b = c->pool[i].hash & nmask;
        c->pool[i].chain = nb[b];
        nb[b] = i;
    }
    free(c->buckets);
    c->buckets = nb;
    c->mask = nmask;
    return true;
}

/* Returns the index of a free pool slot, growing the pool if needed. */
static uint32_t cache_alloc(struct cache *c)
{
    if (c->free_head != NIL) {
        uint32_t i = c->free_head;
        c->free_head = c->pool[i].chain;
        return i;
    }
    if (c->pool_len == c->pool_cap) {
        uint32_t ncap = c->pool_cap ? c->pool_cap * 2 : 1024;
        if (ncap > c->capacity)
            ncap = c->capacity;
        struct entry *np = realloc(c->pool, (size_t)ncap * sizeof *np);
        if (np == NULL)
            return NIL;
        c->pool = np;
        c->pool_cap = ncap;
    }
    return c->pool_len++;
}

/* Finds `key`; on return *link points at the chain slot that references it
 * (or at the terminating NIL of its bucket if absent). */
static uint32_t cache_find(struct cache *c, struct slice key, uint32_t hash,
                           uint32_t **link)
{
    uint32_t *l = &c->buckets[hash & c->mask];
    while (*l != NIL) {
        struct entry *e = &c->pool[*l];
        if (e->hash == hash && slice_eq(e->key, key))
            break;
        l = &e->chain;
    }
    *link = l;
    return *l;
}

static void list_unlink(struct cache *c, uint32_t i)
{
    struct entry *e = &c->pool[i];
    if (e->prev != NIL)
        c->pool[e->prev].next = e->next;
    else
        c->head = e->next;
    if (e->next != NIL)
        c->pool[e->next].prev = e->prev;
    else
        c->tail = e->prev;
}

static void list_push_front(struct cache *c, uint32_t i)
{
    struct entry *e = &c->pool[i];
    e->prev = NIL;
    e->next = c->head;
    if (c->head != NIL)
        c->pool[c->head].prev = i;
    else
        c->tail = i;
    c->head = i;
}

static void cache_touch(struct cache *c, uint32_t i)
{
    if (c->head != i) {
        list_unlink(c, i);
        list_push_front(c, i);
    }
}

/* Unlinks entry i, whose chain slot is *link, and returns it to the pool. */
static void cache_remove_at(struct cache *c, uint32_t *link, uint32_t i)
{
    *link = c->pool[i].chain;
    list_unlink(c, i);
    c->pool[i].chain = c->free_head;
    c->free_head = i;
    c->size--;
}

static void cache_remove(struct cache *c, uint32_t i)
{
    uint32_t *link;
    cache_find(c, c->pool[i].key, c->pool[i].hash, &link);
    cache_remove_at(c, link, i);
}

static bool cache_set(struct cache *c, struct slice key, struct slice value)
{
    uint32_t hash = hash_bytes(key);
    uint32_t *link;
    uint32_t i = cache_find(c, key, hash, &link);

    if (i != NIL) {
        c->pool[i].value = value;
        cache_touch(c, i);
        return true;
    }

    /* Inserting then evicting the LRU is equivalent to evicting first. */
    if (c->size == c->capacity)
        cache_remove(c, c->tail);

    if (c->size >= c->mask + 1 && !cache_rehash(c))
        return false;

    i = cache_alloc(c);
    if (i == NIL)
        return false;

    struct entry *e = &c->pool[i];
    e->key = key;
    e->value = value;
    e->hash = hash;
    uint32_t b = hash & c->mask;
    e->chain = c->buckets[b];
    c->buckets[b] = i;
    list_push_front(c, i);
    c->size++;
    return true;
}

static const struct slice *cache_get(struct cache *c, struct slice key)
{
    uint32_t *link;
    uint32_t i = cache_find(c, key, hash_bytes(key), &link);
    if (i == NIL)
        return NULL;
    cache_touch(c, i);
    return &c->pool[i].value;
}

static bool cache_del(struct cache *c, struct slice key)
{
    uint32_t *link;
    uint32_t i = cache_find(c, key, hash_bytes(key), &link);
    if (i == NIL)
        return false;
    cache_remove_at(c, link, i);
    return true;
}

/* ----------------------------------------------------------------- main */

/* Executes every command line; returns false on allocation failure. */
static bool run(const char *cur, const char *end, struct cache *c,
                struct outbuf *o)
{
    struct slice line, tok[3];

    while (next_line(&cur, end, &line)) {
        size_t n = tokenize(line, tok, 3);
        if (n == 0 || n > 3)
            continue;

        if (n == 3 && slice_is(tok[0], "SET")) {
            if (!cache_set(c, tok[1], tok[2]))
                return false;
        } else if (n == 2 && slice_is(tok[0], "GET")) {
            const struct slice *v = cache_get(c, tok[1]);
            if (v != NULL)
                out_write(o, v->ptr, v->len);
            else
                out_write(o, "NULL", 4);
        } else if (n == 2 && slice_is(tok[0], "DEL")) {
            out_write(o, cache_del(c, tok[1]) ? "1" : "0", 1);
        } else if (n == 1 && slice_is(tok[0], "SIZE")) {
            out_uint(o, c->size);
        }
        /* Anything else is not a valid command and is ignored. */
    }
    return true;
}

int lru_main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    size_t len;
    char *input = read_all(stdin, &len);
    if (input == NULL) {
        fputs("lru: failed to read standard input\n", stderr);
        return EXIT_FAILURE;
    }

    const char *cur = input, *end = input + len;
    struct slice first;
    uint32_t capacity;
    if (!next_line(&cur, end, &first) || !parse_capacity(first, &capacity)) {
        free(input);
        fputs("lru: invalid capacity\n", stderr);
        return EXIT_FAILURE;
    }

    struct cache cache;
    static char obuf[1 << 16];
    struct outbuf out = { .buf = obuf, .cap = sizeof obuf, .out = stdout };
    int status = EXIT_SUCCESS;

    if (!cache_init(&cache, capacity) || !run(cur, end, &cache, &out)) {
        fputs("lru: out of memory\n", stderr);
        status = EXIT_FAILURE;
    }
    out_flush(&out);
    if (fflush(stdout) != 0 || ferror(stdout)) {
        fputs("lru: write error\n", stderr);
        status = EXIT_FAILURE;
    }

    cache_free(&cache);
    free(input);
    return status;
}
