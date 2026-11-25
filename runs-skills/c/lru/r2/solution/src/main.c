/*
 * lru: simulate a least-recently-used cache driven by commands on stdin.
 *
 * The whole input is read into memory once; keys and values are stored as
 * (pointer, length) slices into that buffer, so no per-entry allocation is
 * needed. Entries live in a fixed pool of `capacity` nodes linked into a
 * doubly linked recency list, and are indexed by an open-addressing hash
 * table with linear probing and backward-shift deletion.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NIL UINT32_MAX
#define MAX_CAPACITY 1000000UL

typedef struct {
    const char *ptr;
    size_t len;
} slice;

typedef struct {
    slice key;
    slice value;
    uint64_t hash;
    uint32_t prev;
    uint32_t next;
} node;

typedef struct {
    node *nodes;     /* pool of `capacity` nodes */
    uint32_t *table; /* hash slots holding node indices, NIL if empty */
    size_t mask;     /* table size - 1 (table size is a power of two) */
    uint32_t capacity;
    uint32_t size;
    uint32_t head; /* most recently used */
    uint32_t tail; /* least recently used */
} lru_cache;

/* ---------- output buffering ---------- */

typedef struct {
    char buf[1 << 16];
    size_t len;
} out_buf;

static void out_flush(out_buf *o)
{
    if (o->len > 0) {
        fwrite(o->buf, 1, o->len, stdout);
        o->len = 0;
    }
}

static void out_write(out_buf *o, const char *s, size_t n)
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

static void out_line(out_buf *o, const char *s, size_t n)
{
    out_write(o, s, n);
    out_write(o, "\n", 1);
}

static void out_uint(out_buf *o, unsigned long v)
{
    char tmp[24];
    int w = snprintf(tmp, sizeof tmp, "%lu", v);
    if (w > 0)
        out_line(o, tmp, (size_t)w);
}

/* ---------- hashing ---------- */

static uint64_t hash_bytes(const char *s, size_t n)
{
    /* FNV-1a followed by a 64-bit finalizer for good low-bit dispersion. */
    uint64_t h = 0xcbf29ce484222325ULL;
    for (size_t i = 0; i < n; i++) {
        h ^= (unsigned char)s[i];
        h *= 0x100000001b3ULL;
    }
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdULL;
    h ^= h >> 33;
    return h;
}

static bool slice_eq(slice a, const char *s, size_t n)
{
    return a.len == n && memcmp(a.ptr, s, n) == 0;
}

/* ---------- cache ---------- */

static int lru_init(lru_cache *c, uint32_t capacity)
{
    size_t tsize = 16;
    while (tsize < (size_t)capacity * 2)
        tsize <<= 1;

    c->nodes = malloc((size_t)capacity * sizeof *c->nodes);
    c->table = malloc(tsize * sizeof *c->table);
    if (!c->nodes || !c->table) {
        free(c->nodes);
        free(c->table);
        return -1;
    }
    memset(c->table, 0xff, tsize * sizeof *c->table); /* all NIL */
    c->mask = tsize - 1;
    c->capacity = capacity;
    c->size = 0;
    c->head = NIL;
    c->tail = NIL;
    return 0;
}

static void lru_free(lru_cache *c)
{
    free(c->nodes);
    free(c->table);
}

/* Returns the table slot holding the key, or the empty slot where it belongs. */
static size_t lru_find_slot(const lru_cache *c, const char *key, size_t len, uint64_t h)
{
    size_t i = (size_t)h & c->mask;
    for (;;) {
        uint32_t idx = c->table[i];
        if (idx == NIL)
            return i;
        const node *n = &c->nodes[idx];
        if (n->hash == h && slice_eq(n->key, key, len))
            return i;
        i = (i + 1) & c->mask;
    }
}

/* Empties a slot, shifting later entries of the probe run back into place. */
static void lru_table_remove(lru_cache *c, size_t slot)
{
    size_t hole = slot;
    size_t i = slot;
    for (;;) {
        i = (i + 1) & c->mask;
        uint32_t idx = c->table[i];
        if (idx == NIL)
            break;
        size_t home = (size_t)c->nodes[idx].hash & c->mask;
        /* Move entry i into the hole unless its home lies cyclically in (hole, i]. */
        if (((i - home) & c->mask) >= ((i - hole) & c->mask)) {
            c->table[hole] = idx;
            hole = i;
        }
    }
    c->table[hole] = NIL;
}

static void list_unlink(lru_cache *c, uint32_t idx)
{
    node *n = &c->nodes[idx];
    if (n->prev != NIL)
        c->nodes[n->prev].next = n->next;
    else
        c->head = n->next;
    if (n->next != NIL)
        c->nodes[n->next].prev = n->prev;
    else
        c->tail = n->prev;
}

static void list_push_front(lru_cache *c, uint32_t idx)
{
    node *n = &c->nodes[idx];
    n->prev = NIL;
    n->next = c->head;
    if (c->head != NIL)
        c->nodes[c->head].prev = idx;
    else
        c->tail = idx;
    c->head = idx;
}

static void list_touch(lru_cache *c, uint32_t idx)
{
    if (c->head != idx) {
        list_unlink(c, idx);
        list_push_front(c, idx);
    }
}

/* Removes the node at `idx` (found at table slot `slot`) and moves the last
 * pool node into its place so the pool stays dense. */
static void lru_remove(lru_cache *c, size_t slot, uint32_t idx)
{
    lru_table_remove(c, slot);
    list_unlink(c, idx);

    uint32_t last = --c->size;
    if (idx != last) {
        node *moved = &c->nodes[last];
        size_t mslot = lru_find_slot(c, moved->key.ptr, moved->key.len, moved->hash);
        c->table[mslot] = idx;
        c->nodes[idx] = *moved;
        node *n = &c->nodes[idx];
        if (n->prev != NIL)
            c->nodes[n->prev].next = idx;
        else
            c->head = idx;
        if (n->next != NIL)
            c->nodes[n->next].prev = idx;
        else
            c->tail = idx;
    }
}

static void lru_set(lru_cache *c, slice key, slice value)
{
    uint64_t h = hash_bytes(key.ptr, key.len);
    size_t slot = lru_find_slot(c, key.ptr, key.len, h);
    uint32_t idx = c->table[slot];
    if (idx != NIL) {
        c->nodes[idx].value = value;
        list_touch(c, idx);
        return;
    }

    if (c->size == c->capacity) {
        uint32_t victim = c->tail;
        node *v = &c->nodes[victim];
        size_t vslot = lru_find_slot(c, v->key.ptr, v->key.len, v->hash);
        lru_remove(c, vslot, victim);
        /* Removal may have shifted entries; recompute the insertion slot. */
        slot = lru_find_slot(c, key.ptr, key.len, h);
    }

    idx = c->size++;
    c->nodes[idx] = (node){ .key = key, .value = value, .hash = h };
    c->table[slot] = idx;
    list_push_front(c, idx);
}

static const slice *lru_get(lru_cache *c, slice key)
{
    uint64_t h = hash_bytes(key.ptr, key.len);
    uint32_t idx = c->table[lru_find_slot(c, key.ptr, key.len, h)];
    if (idx == NIL)
        return NULL;
    list_touch(c, idx);
    return &c->nodes[idx].value;
}

static bool lru_del(lru_cache *c, slice key)
{
    uint64_t h = hash_bytes(key.ptr, key.len);
    size_t slot = lru_find_slot(c, key.ptr, key.len, h);
    uint32_t idx = c->table[slot];
    if (idx == NIL)
        return false;
    lru_remove(c, slot, idx);
    return true;
}

/* ---------- input ---------- */

static char *read_all(FILE *f, size_t *out_len)
{
    size_t cap = 1 << 20, len = 0;
    char *buf = malloc(cap);
    if (!buf)
        return NULL;
    for (;;) {
        if (len == cap) {
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
        size_t n = fread(buf + len, 1, cap - len, f);
        len += n;
        if (n == 0) {
            if (ferror(f)) {
                free(buf);
                return NULL;
            }
            break;
        }
    }
    *out_len = len;
    return buf;
}

/* Splits the next space-separated token off [*p, end). */
static slice next_token(const char **p, const char *end)
{
    const char *s = *p;
    while (s < end && *s == ' ')
        s++;
    const char *e = s;
    while (e < end && *e != ' ')
        e++;
    *p = e;
    return (slice){ .ptr = s, .len = (size_t)(e - s) };
}

static bool parse_capacity(slice tok, uint32_t *out)
{
    if (tok.len == 0)
        return false;
    unsigned long v = 0;
    for (size_t i = 0; i < tok.len; i++) {
        char ch = tok.ptr[i];
        if (ch < '0' || ch > '9')
            return false;
        v = v * 10 + (unsigned long)(ch - '0');
        if (v > MAX_CAPACITY)
            return false;
    }
    if (v == 0)
        return false;
    *out = (uint32_t)v;
    return true;
}

static void run_command(lru_cache *c, out_buf *o, const char *p, const char *end)
{
    slice cmd = next_token(&p, end);
    slice key = next_token(&p, end);

    if (slice_eq(cmd, "SET", 3)) {
        slice value = next_token(&p, end);
        if (key.len > 0 && value.len > 0)
            lru_set(c, key, value);
    } else if (slice_eq(cmd, "GET", 3)) {
        if (key.len == 0)
            return;
        const slice *v = lru_get(c, key);
        if (v)
            out_line(o, v->ptr, v->len);
        else
            out_line(o, "NULL", 4);
    } else if (slice_eq(cmd, "DEL", 3)) {
        if (key.len == 0)
            return;
        out_line(o, lru_del(c, key) ? "1" : "0", 1);
    } else if (slice_eq(cmd, "SIZE", 4)) {
        out_uint(o, c->size);
    }
}

/* Returns the end of the line starting at p, excluding "\n" and a trailing "\r". */
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
    size_t len = 0;
    char *input = read_all(stdin, &len);
    if (!input) {
        fputs("lru: failed to read input\n", stderr);
        return EXIT_FAILURE;
    }

    const char *p = input;
    const char *end = input + len;
    const char *next;
    const char *le = line_end(p, end, &next);
    uint32_t capacity;
    if (!parse_capacity(next_token(&p, le), &capacity)) {
        fputs("lru: invalid capacity\n", stderr);
        free(input);
        return EXIT_FAILURE;
    }
    p = next;

    lru_cache cache;
    if (lru_init(&cache, capacity) != 0) {
        fputs("lru: out of memory\n", stderr);
        free(input);
        return EXIT_FAILURE;
    }

    static out_buf out;
    while (p < end) {
        le = line_end(p, end, &next);
        run_command(&cache, &out, p, le);
        p = next;
    }
    out_flush(&out);

    lru_free(&cache);
    free(input);
    return fflush(stdout) == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
