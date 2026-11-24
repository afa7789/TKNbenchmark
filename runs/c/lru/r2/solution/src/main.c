/*
 * lru — simulate an LRU cache driven by commands on standard input.
 *
 * The whole input is read into memory once; keys and values are stored as
 * slices of that buffer, so no per-entry allocation is needed. Entries live
 * in a fixed pool linked into a doubly linked recency list and indexed by an
 * open-addressing hash table (linear probing, backward-shift deletion).
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NIL UINT32_MAX

typedef struct {
    const char *ptr;
    uint32_t len;
} Slice;

typedef struct {
    Slice key;
    Slice value;
    uint32_t hash;
    uint32_t prev; /* towards most recently used */
    uint32_t next; /* towards least recently used */
} Entry;

typedef struct {
    Entry *entries;    /* pool of `capacity` entries */
    uint32_t *slots;   /* entry index + 1; 0 means empty */
    uint32_t mask;     /* slot count - 1 (power of two) */
    uint32_t capacity; /* maximum number of keys held */
    uint32_t size;     /* number of keys held */
    uint32_t head;     /* most recently used, or NIL */
    uint32_t tail;     /* least recently used, or NIL */
    uint32_t free_top; /* head of free-entry stack (linked via next), or NIL */
    uint32_t unused;   /* first never-used pool index */
} Cache;

static void *xmalloc(size_t n)
{
    void *p = malloc(n);
    if (p == NULL) {
        fputs("lru: out of memory\n", stderr);
        exit(EXIT_FAILURE);
    }
    return p;
}

static uint32_t hash_bytes(const char *s, uint32_t len)
{
    /* FNV-1a followed by a murmur3 finalizer for good low-bit mixing. */
    uint32_t h = 2166136261u;
    for (uint32_t i = 0; i < len; i++) {
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

static bool slice_eq(Slice a, Slice b)
{
    return a.len == b.len && memcmp(a.ptr, b.ptr, a.len) == 0;
}

static void cache_init(Cache *c, uint32_t capacity)
{
    uint64_t want = (uint64_t)capacity * 2;
    uint64_t nslots = 16;
    while (nslots < want)
        nslots <<= 1;

    c->entries = xmalloc((size_t)capacity * sizeof *c->entries);
    c->slots = calloc((size_t)nslots, sizeof *c->slots);
    if (c->slots == NULL) {
        fputs("lru: out of memory\n", stderr);
        exit(EXIT_FAILURE);
    }
    c->mask = (uint32_t)(nslots - 1);
    c->capacity = capacity;
    c->size = 0;
    c->head = c->tail = NIL;
    c->free_top = NIL;
    c->unused = 0;
}

static void cache_free(Cache *c)
{
    free(c->entries);
    free(c->slots);
}

/* Returns the slot holding `key`, or the empty slot where it would go. */
static uint32_t find_slot(const Cache *c, Slice key, uint32_t hash)
{
    uint32_t i = hash & c->mask;
    for (;;) {
        uint32_t s = c->slots[i];
        if (s == 0)
            return i;
        const Entry *e = &c->entries[s - 1];
        if (e->hash == hash && slice_eq(e->key, key))
            return i;
        i = (i + 1) & c->mask;
    }
}

/* Empties slot `i`, shifting later cluster members back to keep probes valid. */
static void remove_slot(Cache *c, uint32_t i)
{
    uint32_t j = i;
    for (;;) {
        j = (j + 1) & c->mask;
        uint32_t s = c->slots[j];
        if (s == 0)
            break;
        uint32_t home = c->entries[s - 1].hash & c->mask;
        /* Move s into the hole at i unless its home lies cyclically in (i, j]. */
        bool stays = (i <= j) ? (i < home && home <= j) : (i < home || home <= j);
        if (!stays) {
            c->slots[i] = s;
            i = j;
        }
    }
    c->slots[i] = 0;
}

static void list_unlink(Cache *c, uint32_t idx)
{
    Entry *e = &c->entries[idx];
    if (e->prev != NIL)
        c->entries[e->prev].next = e->next;
    else
        c->head = e->next;
    if (e->next != NIL)
        c->entries[e->next].prev = e->prev;
    else
        c->tail = e->prev;
}

static void list_push_front(Cache *c, uint32_t idx)
{
    Entry *e = &c->entries[idx];
    e->prev = NIL;
    e->next = c->head;
    if (c->head != NIL)
        c->entries[c->head].prev = idx;
    else
        c->tail = idx;
    c->head = idx;
}

static void touch(Cache *c, uint32_t idx)
{
    if (c->head != idx) {
        list_unlink(c, idx);
        list_push_front(c, idx);
    }
}

/* Removes the entry in slot `slot` from the cache and recycles it. */
static void remove_at(Cache *c, uint32_t slot)
{
    uint32_t idx = c->slots[slot] - 1;
    remove_slot(c, slot);
    list_unlink(c, idx);
    c->entries[idx].next = c->free_top;
    c->free_top = idx;
    c->size--;
}

static uint32_t alloc_entry(Cache *c)
{
    if (c->free_top != NIL) {
        uint32_t idx = c->free_top;
        c->free_top = c->entries[idx].next;
        return idx;
    }
    return c->unused++;
}

static void cache_set(Cache *c, Slice key, Slice value)
{
    uint32_t hash = hash_bytes(key.ptr, key.len);
    uint32_t slot = find_slot(c, key, hash);

    if (c->slots[slot] != 0) {
        uint32_t idx = c->slots[slot] - 1;
        c->entries[idx].value = value;
        touch(c, idx);
        return;
    }

    if (c->size == c->capacity) {
        /* Inserting would exceed capacity: evict the least recently used. */
        const Entry *lru = &c->entries[c->tail];
        remove_at(c, find_slot(c, lru->key, lru->hash));
        slot = find_slot(c, key, hash); /* the table may have shifted */
    }

    uint32_t idx = alloc_entry(c);
    Entry *e = &c->entries[idx];
    e->key = key;
    e->value = value;
    e->hash = hash;
    c->slots[slot] = idx + 1;
    list_push_front(c, idx);
    c->size++;
}

static const Entry *cache_get(Cache *c, Slice key)
{
    uint32_t slot = find_slot(c, key, hash_bytes(key.ptr, key.len));
    if (c->slots[slot] == 0)
        return NULL;
    uint32_t idx = c->slots[slot] - 1;
    touch(c, idx);
    return &c->entries[idx];
}

static bool cache_del(Cache *c, Slice key)
{
    uint32_t slot = find_slot(c, key, hash_bytes(key.ptr, key.len));
    if (c->slots[slot] == 0)
        return false;
    remove_at(c, slot);
    return true;
}

/* ---------- input / output ---------- */

static char *read_all(FILE *f, size_t *out_len)
{
    size_t cap = 1 << 20, len = 0;
    char *buf = xmalloc(cap);
    for (;;) {
        if (len == cap) {
            cap *= 2;
            char *nb = realloc(buf, cap);
            if (nb == NULL) {
                free(buf);
                fputs("lru: out of memory\n", stderr);
                exit(EXIT_FAILURE);
            }
            buf = nb;
        }
        size_t n = fread(buf + len, 1, cap - len, f);
        len += n;
        if (n == 0)
            break;
    }
    *out_len = len;
    return buf;
}

typedef struct {
    char *buf;
    size_t len;
    size_t cap;
} Output;

static void out_flush(Output *o)
{
    if (o->len > 0) {
        fwrite(o->buf, 1, o->len, stdout);
        o->len = 0;
    }
}

static void out_line(Output *o, const char *s, size_t n)
{
    if (o->cap - o->len < n + 1)
        out_flush(o);
    if (n + 1 > o->cap) {
        fwrite(s, 1, n, stdout);
        fputc('\n', stdout);
        return;
    }
    memcpy(o->buf + o->len, s, n);
    o->len += n;
    o->buf[o->len++] = '\n';
}

static void out_uint(Output *o, uint32_t v)
{
    char tmp[16];
    int n = snprintf(tmp, sizeof tmp, "%u", (unsigned)v);
    out_line(o, tmp, (size_t)n);
}

/* Splits the next space-separated token off *p (bounded by end). */
static Slice next_token(const char **p, const char *end)
{
    const char *s = *p;
    while (s < end && *s == ' ')
        s++;
    const char *t = s;
    while (t < end && *t != ' ')
        t++;
    *p = t;
    return (Slice){ s, (uint32_t)(t - s) };
}

static bool token_is(Slice t, const char *word)
{
    size_t n = strlen(word);
    return t.len == n && memcmp(t.ptr, word, n) == 0;
}

static uint32_t parse_capacity(const char *s, const char *end)
{
    while (s < end && (*s == ' ' || *s == '\t'))
        s++;
    uint64_t v = 0;
    while (s < end && *s >= '0' && *s <= '9') {
        v = v * 10 + (uint64_t)(*s - '0');
        if (v > UINT32_MAX)
            v = UINT32_MAX;
        s++;
    }
    if (v < 1)
        v = 1;
    return (uint32_t)v;
}

int main(void)
{
    size_t len;
    char *input = read_all(stdin, &len);
    const char *p = input;
    const char *end = input + len;

    const char *nl = memchr(p, '\n', len);
    const char *line_end = nl ? nl : end;
    uint32_t capacity = parse_capacity(p, line_end);
    p = nl ? nl + 1 : end;

    Cache cache;
    cache_init(&cache, capacity);

    static char out_buf[1 << 16];
    Output out = { out_buf, 0, sizeof out_buf };

    while (p < end) {
        nl = memchr(p, '\n', (size_t)(end - p));
        line_end = nl ? nl : end;
        const char *next = nl ? nl + 1 : end;
        if (line_end > p && line_end[-1] == '\r')
            line_end--;

        const char *q = p;
        Slice cmd = next_token(&q, line_end);
        if (token_is(cmd, "SET")) {
            Slice key = next_token(&q, line_end);
            Slice value = next_token(&q, line_end);
            if (key.len > 0)
                cache_set(&cache, key, value);
        } else if (token_is(cmd, "GET")) {
            Slice key = next_token(&q, line_end);
            const Entry *e = cache_get(&cache, key);
            if (e != NULL)
                out_line(&out, e->value.ptr, e->value.len);
            else
                out_line(&out, "NULL", 4);
        } else if (token_is(cmd, "DEL")) {
            Slice key = next_token(&q, line_end);
            out_line(&out, cache_del(&cache, key) ? "1" : "0", 1);
        } else if (token_is(cmd, "SIZE")) {
            out_uint(&out, cache.size);
        }
        p = next;
    }

    out_flush(&out);
    fflush(stdout);
    cache_free(&cache);
    free(input);
    return EXIT_SUCCESS;
}
