/*
 * lru: simulate an LRU cache driven by commands on standard input.
 *
 * The whole input is read into memory once; keys and values are stored as
 * slices into that buffer, so no per-command allocation happens. Entries live
 * in a fixed pool of nodes linked into a doubly linked recency list and into
 * hash-bucket chains, all addressed by 32-bit indices.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NIL UINT32_MAX
#define CAPACITY_MAX 1000000UL

typedef struct {
    const char *ptr;
    uint32_t len;
} Slice;

typedef struct {
    Slice key;
    Slice val;
    uint32_t hash;
    uint32_t prev;  /* towards most recently used */
    uint32_t next;  /* towards least recently used */
    uint32_t chain; /* next node in the same bucket, or free-list link */
} Node;

typedef struct {
    Node *nodes;
    uint32_t *buckets;
    uint32_t mask;
    uint32_t capacity;
    uint32_t size;
    uint32_t head; /* most recently used */
    uint32_t tail; /* least recently used */
    uint32_t free_list;
} Lru;

/* ---------- output buffering ---------- */

typedef struct {
    char buf[1 << 16];
    size_t len;
} Out;

static void out_flush(Out *o)
{
    if (o->len > 0) {
        fwrite(o->buf, 1, o->len, stdout);
        o->len = 0;
    }
}

static void out_write(Out *o, const char *s, size_t n)
{
    if (n > sizeof o->buf - o->len) {
        out_flush(o);
        if (n > sizeof o->buf) {
            fwrite(s, 1, n, stdout);
            return;
        }
    }
    memcpy(o->buf + o->len, s, n);
    o->len += n;
}

static void out_line(Out *o, const char *s, size_t n)
{
    out_write(o, s, n);
    out_write(o, "\n", 1);
}

static void out_uint(Out *o, unsigned long v)
{
    char tmp[24];
    size_t i = sizeof tmp;
    tmp[--i] = '\n';
    do {
        tmp[--i] = (char)('0' + v % 10);
        v /= 10;
    } while (v != 0);
    out_write(o, tmp + i, sizeof tmp - i);
}

/* ---------- LRU cache ---------- */

static uint32_t hash_bytes(const char *s, uint32_t n)
{
    /* FNV-1a, finished with a murmur-style avalanche. */
    uint32_t h = 2166136261u;
    for (uint32_t i = 0; i < n; i++) {
        h ^= (unsigned char)s[i];
        h *= 16777619u;
    }
    h ^= h >> 16;
    h *= 0x85ebca6bu;
    h ^= h >> 13;
    h *= 0xc2b2ae35u;
    h ^= h >> 16;
    return h;
}

static int lru_init(Lru *c, uint32_t capacity)
{
    uint32_t nbuckets = 1;
    while (nbuckets < 2 * capacity)
        nbuckets <<= 1;

    c->nodes = malloc((size_t)capacity * sizeof *c->nodes);
    c->buckets = malloc((size_t)nbuckets * sizeof *c->buckets);
    if (!c->nodes || !c->buckets) {
        free(c->nodes);
        free(c->buckets);
        return -1;
    }
    for (uint32_t i = 0; i < nbuckets; i++)
        c->buckets[i] = NIL;
    for (uint32_t i = 0; i < capacity; i++)
        c->nodes[i].chain = i + 1 < capacity ? i + 1 : NIL;

    c->mask = nbuckets - 1;
    c->capacity = capacity;
    c->size = 0;
    c->head = c->tail = NIL;
    c->free_list = 0;
    return 0;
}

static void lru_free(Lru *c)
{
    free(c->nodes);
    free(c->buckets);
}

static void list_unlink(Lru *c, uint32_t i)
{
    Node *n = &c->nodes[i];
    if (n->prev != NIL)
        c->nodes[n->prev].next = n->next;
    else
        c->head = n->next;
    if (n->next != NIL)
        c->nodes[n->next].prev = n->prev;
    else
        c->tail = n->prev;
}

static void list_push_front(Lru *c, uint32_t i)
{
    Node *n = &c->nodes[i];
    n->prev = NIL;
    n->next = c->head;
    if (c->head != NIL)
        c->nodes[c->head].prev = i;
    else
        c->tail = i;
    c->head = i;
}

static void list_touch(Lru *c, uint32_t i)
{
    if (c->head != i) {
        list_unlink(c, i);
        list_push_front(c, i);
    }
}

/* Returns the address of the link that points at the matching node (or at
 * NIL at the end of the chain), so callers can both find and unlink. */
static uint32_t *lru_slot(Lru *c, Slice key, uint32_t hash)
{
    uint32_t *link = &c->buckets[hash & c->mask];
    while (*link != NIL) {
        const Node *n = &c->nodes[*link];
        if (n->hash == hash && n->key.len == key.len &&
            memcmp(n->key.ptr, key.ptr, key.len) == 0)
            break;
        link = &c->nodes[*link].chain;
    }
    return link;
}

static void lru_remove_at(Lru *c, uint32_t *link)
{
    uint32_t i = *link;
    *link = c->nodes[i].chain;
    list_unlink(c, i);
    c->nodes[i].chain = c->free_list;
    c->free_list = i;
    c->size--;
}

static void lru_evict(Lru *c)
{
    const Node *victim = &c->nodes[c->tail];
    lru_remove_at(c, lru_slot(c, victim->key, victim->hash));
}

static void lru_set(Lru *c, Slice key, Slice val)
{
    uint32_t hash = hash_bytes(key.ptr, key.len);
    uint32_t *link = lru_slot(c, key, hash);
    if (*link != NIL) {
        c->nodes[*link].val = val;
        list_touch(c, *link);
        return;
    }
    if (c->size == c->capacity) {
        lru_evict(c);
        /* Eviction may have rewritten the chain we were about to extend. */
        link = lru_slot(c, key, hash);
    }
    uint32_t i = c->free_list;
    Node *n = &c->nodes[i];
    c->free_list = n->chain;
    n->key = key;
    n->val = val;
    n->hash = hash;
    n->chain = NIL;
    *link = i;
    list_push_front(c, i);
    c->size++;
}

static const Slice *lru_get(Lru *c, Slice key)
{
    uint32_t i = *lru_slot(c, key, hash_bytes(key.ptr, key.len));
    if (i == NIL)
        return NULL;
    list_touch(c, i);
    return &c->nodes[i].val;
}

static int lru_del(Lru *c, Slice key)
{
    uint32_t *link = lru_slot(c, key, hash_bytes(key.ptr, key.len));
    if (*link == NIL)
        return 0;
    lru_remove_at(c, link);
    return 1;
}

/* ---------- input ---------- */

static char *read_all(FILE *f, size_t *len_out)
{
    size_t cap = 1 << 20, len = 0;
    char *buf = malloc(cap);
    if (!buf)
        return NULL;
    for (;;) {
        len += fread(buf + len, 1, cap - len, f);
        if (len < cap) {
            if (ferror(f)) {
                free(buf);
                return NULL;
            }
            break;
        }
        if (cap > SIZE_MAX / 2) {
            free(buf);
            return NULL;
        }
        char *p = realloc(buf, cap * 2);
        if (!p) {
            free(buf);
            return NULL;
        }
        buf = p;
        cap *= 2;
    }
    *len_out = len;
    return buf;
}

/* Splits the next space-separated token off [*p, end). */
static Slice next_token(const char **p, const char *end)
{
    const char *s = *p;
    while (s < end && *s == ' ')
        s++;
    const char *t = s;
    while (t < end && *t != ' ')
        t++;
    *p = t;
    return (Slice){s, (uint32_t)(t - s)};
}

static int slice_eq(Slice s, const char *lit)
{
    size_t n = strlen(lit);
    return s.len == n && memcmp(s.ptr, lit, n) == 0;
}

static int parse_capacity(Slice s, uint32_t *out)
{
    unsigned long v = 0;
    if (s.len == 0)
        return -1;
    for (uint32_t i = 0; i < s.len; i++) {
        unsigned char ch = (unsigned char)s.ptr[i];
        if (ch < '0' || ch > '9')
            return -1;
        v = v * 10 + (ch - '0');
        if (v > CAPACITY_MAX)
            return -1;
    }
    if (v == 0)
        return -1;
    *out = (uint32_t)v;
    return 0;
}

static void run_command(Lru *c, Out *o, const char *line, const char *end)
{
    Slice cmd = next_token(&line, end);
    if (slice_eq(cmd, "SET")) {
        Slice key = next_token(&line, end);
        Slice val = next_token(&line, end);
        if (key.len > 0 && val.len > 0)
            lru_set(c, key, val);
    } else if (slice_eq(cmd, "GET")) {
        Slice key = next_token(&line, end);
        const Slice *val = lru_get(c, key);
        if (val)
            out_line(o, val->ptr, val->len);
        else
            out_line(o, "NULL", 4);
    } else if (slice_eq(cmd, "DEL")) {
        Slice key = next_token(&line, end);
        out_line(o, lru_del(c, key) ? "1" : "0", 1);
    } else if (slice_eq(cmd, "SIZE")) {
        out_uint(o, c->size);
    }
}

/* Returns the end of the line starting at p (trailing '\r' excluded) and
 * stores the start of the following line in *next. */
static const char *line_end(const char *p, const char *end, const char **next)
{
    const char *nl = memchr(p, '\n', (size_t)(end - p));
    const char *e = nl ? nl : end;
    *next = nl ? nl + 1 : end;
    if (e > p && e[-1] == '\r')
        e--;
    return e;
}

int main(void)
{
    static Out out;
    size_t len;
    char *input = read_all(stdin, &len);
    if (!input) {
        fputs("lru: failed to read input\n", stderr);
        return EXIT_FAILURE;
    }

    const char *p = input, *end = input + len, *next;
    const char *e = line_end(p, end, &next);
    Slice cap_tok = next_token(&p, e);
    uint32_t capacity;
    if (parse_capacity(cap_tok, &capacity) != 0) {
        fputs("lru: invalid capacity\n", stderr);
        free(input);
        return EXIT_FAILURE;
    }

    Lru cache;
    if (lru_init(&cache, capacity) != 0) {
        fputs("lru: out of memory\n", stderr);
        free(input);
        return EXIT_FAILURE;
    }

    for (p = next; p < end; p = next) {
        e = line_end(p, end, &next);
        run_command(&cache, &out, p, e);
    }

    out_flush(&out);
    lru_free(&cache);
    free(input);
    return EXIT_SUCCESS;
}
