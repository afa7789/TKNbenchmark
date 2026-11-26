/*
 * `app lru`: LRU cache simulator (see SPEC.md, section "lru").
 *
 * Design
 * ------
 * All of standard input is read into one buffer up front. Keys and values
 * are never copied: cache entries point straight into that buffer, which
 * lives until the command finishes.
 *
 * Entries live in a fixed pool of `capacity` nodes, addressed by 32-bit
 * indices. Index 0 is reserved as the sentinel of a circular doubly linked
 * recency list (most recently used right after the sentinel, least recently
 * used right before it), and also serves as the "null" link everywhere else.
 * A separately chained hash table maps keys to node indices. Every command
 * is therefore O(1) expected time, and memory is bounded by the capacity.
 */
#include "lru.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LRU_MAX_CAPACITY 1000000UL
#define NIL 0u

struct node {
    const char *key;
    const char *val;
    uint32_t klen;
    uint32_t vlen;
    uint32_t hash;
    uint32_t prev;   /* recency list */
    uint32_t next;   /* recency list; free-list link when unused */
    uint32_t chain;  /* next node in the same hash bucket */
};

struct lru {
    struct node *nodes;     /* nodes[0] is the list sentinel */
    uint32_t *buckets;      /* head node index per bucket, NIL if empty */
    uint32_t mask;          /* bucket count - 1 (power of two) */
    uint32_t capacity;
    uint32_t size;
    uint32_t used;          /* nodes ever handed out (bump allocator) */
    uint32_t free_list;     /* recycled nodes, linked through `next` */
};

/* ---------- hashing ---------- */

static uint32_t hash_bytes(const char *s, size_t n)
{
    /* 64-bit FNV-1a with a final avalanche, folded to 32 bits. */
    uint64_t h = 0xcbf29ce484222325ULL;
    for (size_t i = 0; i < n; i++) {
        h ^= (unsigned char)s[i];
        h *= 0x100000001b3ULL;
    }
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdULL;
    h ^= h >> 33;
    return (uint32_t)h;
}

/* ---------- cache ---------- */

static bool lru_init(struct lru *c, uint32_t capacity)
{
    size_t nbuckets = 1;
    while (nbuckets < capacity)
        nbuckets <<= 1;

    *c = (struct lru){ .capacity = capacity, .mask = (uint32_t)(nbuckets - 1) };
    c->nodes = malloc(((size_t)capacity + 1) * sizeof *c->nodes);
    c->buckets = calloc(nbuckets, sizeof *c->buckets);
    if (c->nodes == NULL || c->buckets == NULL) {
        free(c->nodes);
        free(c->buckets);
        return false;
    }
    c->nodes[NIL].prev = NIL;
    c->nodes[NIL].next = NIL;
    return true;
}

static void lru_free(struct lru *c)
{
    free(c->nodes);
    free(c->buckets);
}

static void list_unlink(struct lru *c, uint32_t i)
{
    struct node *n = &c->nodes[i];
    c->nodes[n->prev].next = n->next;
    c->nodes[n->next].prev = n->prev;
}

static void list_push_front(struct lru *c, uint32_t i)
{
    struct node *n = &c->nodes[i];
    n->prev = NIL;
    n->next = c->nodes[NIL].next;
    c->nodes[n->next].prev = i;
    c->nodes[NIL].next = i;
}

static void touch(struct lru *c, uint32_t i)
{
    if (c->nodes[NIL].next != i) {
        list_unlink(c, i);
        list_push_front(c, i);
    }
}

/*
 * Find `key`. Returns its node index or NIL. If `link` is non-NULL it
 * receives the address of the link that points at the node (or at NIL when
 * absent), so the caller can unlink it from its bucket in O(1).
 */
static uint32_t lookup(struct lru *c, const char *key, uint32_t klen,
                       uint32_t hash, uint32_t **link)
{
    uint32_t *p = &c->buckets[hash & c->mask];
    while (*p != NIL) {
        const struct node *n = &c->nodes[*p];
        if (n->hash == hash && n->klen == klen && memcmp(n->key, key, klen) == 0)
            break;
        p = &c->nodes[*p].chain;
    }
    if (link != NULL)
        *link = p;
    return *p;
}

/* Remove node `i` (whose bucket link is `*link`) and recycle it. */
static void remove_node(struct lru *c, uint32_t i, uint32_t *link)
{
    *link = c->nodes[i].chain;
    list_unlink(c, i);
    c->nodes[i].next = c->free_list;
    c->free_list = i;
    c->size--;
}

static void evict_lru(struct lru *c)
{
    uint32_t victim = c->nodes[NIL].prev;
    struct node *v = &c->nodes[victim];
    uint32_t *link;
    lookup(c, v->key, v->klen, v->hash, &link);
    remove_node(c, victim, link);
}

static uint32_t alloc_node(struct lru *c)
{
    if (c->free_list != NIL) {
        uint32_t i = c->free_list;
        c->free_list = c->nodes[i].next;
        return i;
    }
    return ++c->used;
}

static void lru_set(struct lru *c, const char *key, uint32_t klen,
                    const char *val, uint32_t vlen)
{
    uint32_t hash = hash_bytes(key, klen);
    uint32_t i = lookup(c, key, klen, hash, NULL);

    if (i != NIL) {
        c->nodes[i].val = val;
        c->nodes[i].vlen = vlen;
        touch(c, i);
        return;
    }

    /*
     * Inserting a new key into a full cache would leave C + 1 keys, so the
     * least recently used one goes. Evicting first is equivalent, and keeps
     * the pool at exactly C nodes.
     */
    if (c->size == c->capacity)
        evict_lru(c);

    i = alloc_node(c);
    struct node *n = &c->nodes[i];
    n->key = key;
    n->klen = klen;
    n->val = val;
    n->vlen = vlen;
    n->hash = hash;
    uint32_t *bucket = &c->buckets[hash & c->mask];
    n->chain = *bucket;
    *bucket = i;
    list_push_front(c, i);
    c->size++;
}

static const struct node *lru_get(struct lru *c, const char *key, uint32_t klen)
{
    uint32_t i = lookup(c, key, klen, hash_bytes(key, klen), NULL);
    if (i == NIL)
        return NULL;
    touch(c, i);
    return &c->nodes[i];
}

static bool lru_del(struct lru *c, const char *key, uint32_t klen)
{
    uint32_t *link;
    uint32_t i = lookup(c, key, klen, hash_bytes(key, klen), &link);
    if (i == NIL)
        return false;
    remove_node(c, i, link);
    return true;
}

/* ---------- input ---------- */

/* Read all of `in` into a heap buffer. Returns NULL on failure. */
static char *read_all(FILE *in, size_t *len_out)
{
    size_t cap = 1 << 16;
    size_t len = 0;
    char *buf = malloc(cap);
    if (buf == NULL)
        return NULL;

    for (;;) {
        if (len == cap) {
            char *grown = realloc(buf, cap * 2);
            if (grown == NULL) {
                free(buf);
                return NULL;
            }
            buf = grown;
            cap *= 2;
        }
        size_t got = fread(buf + len, 1, cap - len, in);
        len += got;
        if (got == 0) {
            if (ferror(in)) {
                free(buf);
                return NULL;
            }
            break;
        }
    }
    *len_out = len;
    return buf;
}

struct slice {
    const char *ptr;
    size_t len;
};

/* Pop the next line from `*rest` (without its terminator). */
static bool next_line(struct slice *rest, struct slice *line)
{
    if (rest->len == 0)
        return false;

    const char *nl = memchr(rest->ptr, '\n', rest->len);
    size_t n = nl != NULL ? (size_t)(nl - rest->ptr) : rest->len;

    line->ptr = rest->ptr;
    line->len = n;
    if (n > 0 && line->ptr[n - 1] == '\r')
        line->len--;

    size_t consumed = nl != NULL ? n + 1 : n;
    rest->ptr += consumed;
    rest->len -= consumed;
    return true;
}

/* Pop the next space-separated token from `*line`. */
static struct slice next_token(struct slice *line)
{
    const char *sp = memchr(line->ptr, ' ', line->len);
    size_t n = sp != NULL ? (size_t)(sp - line->ptr) : line->len;
    struct slice tok = { line->ptr, n };
    size_t consumed = sp != NULL ? n + 1 : n;
    line->ptr += consumed;
    line->len -= consumed;
    return tok;
}

static bool slice_eq(struct slice s, const char *lit)
{
    size_t n = strlen(lit);
    return s.len == n && memcmp(s.ptr, lit, n) == 0;
}

/* Parse the capacity line; returns 0 if it is not a valid capacity. */
static uint32_t parse_capacity(struct slice s)
{
    size_t i = 0;
    while (i < s.len && (s.ptr[i] == ' ' || s.ptr[i] == '\t'))
        i++;

    unsigned long value = 0;
    size_t digits = 0;
    for (; i < s.len && s.ptr[i] >= '0' && s.ptr[i] <= '9'; i++, digits++) {
        value = value * 10 + (unsigned long)(s.ptr[i] - '0');
        if (value > LRU_MAX_CAPACITY)
            return 0;
    }

    while (i < s.len && (s.ptr[i] == ' ' || s.ptr[i] == '\t'))
        i++;
    if (digits == 0 || i != s.len)
        return 0;
    return (uint32_t)value;
}

/* ---------- driver ---------- */

static void run(struct lru *c, struct slice rest, FILE *out)
{
    struct slice line;
    while (next_line(&rest, &line)) {
        struct slice cmd = next_token(&line);

        if (slice_eq(cmd, "GET")) {
            struct slice key = next_token(&line);
            const struct node *n = lru_get(c, key.ptr, (uint32_t)key.len);
            if (n != NULL) {
                fwrite(n->val, 1, n->vlen, out);
                putc('\n', out);
            } else {
                fputs("NULL\n", out);
            }
        } else if (slice_eq(cmd, "SET")) {
            struct slice key = next_token(&line);
            struct slice val = next_token(&line);
            lru_set(c, key.ptr, (uint32_t)key.len, val.ptr, (uint32_t)val.len);
        } else if (slice_eq(cmd, "DEL")) {
            struct slice key = next_token(&line);
            fputs(lru_del(c, key.ptr, (uint32_t)key.len) ? "1\n" : "0\n", out);
        } else if (slice_eq(cmd, "SIZE")) {
            fprintf(out, "%" PRIu32 "\n", c->size);
        }
        /* Blank or unrecognised lines are ignored. */
    }
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

    struct slice rest = { input, len };
    struct slice first;
    if (!next_line(&rest, &first)) {
        free(input);
        return EXIT_SUCCESS; /* empty input: nothing to do */
    }

    uint32_t capacity = parse_capacity(first);
    if (capacity == 0) {
        fputs("lru: invalid capacity\n", stderr);
        free(input);
        return EXIT_FAILURE;
    }

    struct lru cache;
    if (!lru_init(&cache, capacity)) {
        fputs("lru: out of memory\n", stderr);
        free(input);
        return EXIT_FAILURE;
    }

    static char outbuf[1 << 16];
    setvbuf(stdout, outbuf, _IOFBF, sizeof outbuf);

    run(&cache, rest, stdout);

    int status = EXIT_SUCCESS;
    if (fflush(stdout) != 0 || ferror(stdout)) {
        fputs("lru: write error\n", stderr);
        status = EXIT_FAILURE;
    }

    lru_free(&cache);
    free(input);
    return status;
}
