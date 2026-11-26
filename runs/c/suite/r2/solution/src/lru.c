/* lru: simulate an LRU cache driven by SET/GET/DEL/SIZE commands on stdin. */
#include "commands.h"
#include "hash.h"
#include "io.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#define NIL UINT32_MAX

/* Keys and values point into the input buffer, which outlives the cache. */
typedef struct {
    const char *key;
    const char *val;
    uint64_t hash;
    uint32_t klen;
    uint32_t vlen;
    uint32_t prev; /* towards most recently used */
    uint32_t next; /* towards least recently used; free-list link when unused */
} Node;

typedef struct {
    Node *nodes;
    uint32_t nodes_len; /* nodes ever allocated */
    uint32_t nodes_cap;
    uint32_t free_head;

    uint32_t *slots; /* node index or NIL; linear probing, no tombstones */
    size_t mask;

    uint32_t head; /* most recently used */
    uint32_t tail; /* least recently used */
    uint32_t size;
    uint32_t capacity;
} Cache;

static void cache_init(Cache *c, uint32_t capacity)
{
    *c = (Cache){ .free_head = NIL, .head = NIL, .tail = NIL, .capacity = capacity };
    c->nodes_cap = 64;
    c->nodes = xmalloc(c->nodes_cap * sizeof *c->nodes);
    size_t slots = 128;
    c->slots = xmalloc(slots * sizeof *c->slots);
    memset(c->slots, 0xff, slots * sizeof *c->slots);
    c->mask = slots - 1;
}

static void cache_free(Cache *c)
{
    free(c->nodes);
    free(c->slots);
}

/* ---- recency list ---- */

static void list_unlink(Cache *c, uint32_t i)
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

static void list_push_front(Cache *c, uint32_t i)
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

static void list_touch(Cache *c, uint32_t i)
{
    if (c->head != i) {
        list_unlink(c, i);
        list_push_front(c, i);
    }
}

/* ---- hash index ---- */

/* Return the slot holding key, or the empty slot where it would go. */
static size_t index_find(const Cache *c, const char *key, uint32_t klen, uint64_t h)
{
    size_t s = h & c->mask;
    for (;;) {
        uint32_t i = c->slots[s];
        if (i == NIL)
            return s;
        const Node *n = &c->nodes[i];
        if (n->hash == h && n->klen == klen && memcmp(n->key, key, klen) == 0)
            return s;
        s = (s + 1) & c->mask;
    }
}

static void index_grow(Cache *c)
{
    size_t cap = (c->mask + 1) * 2;
    uint32_t *slots = xmalloc(cap * sizeof *slots);
    memset(slots, 0xff, cap * sizeof *slots);
    size_t mask = cap - 1;
    for (size_t s = 0; s <= c->mask; s++) {
        uint32_t i = c->slots[s];
        if (i == NIL)
            continue;
        size_t t = c->nodes[i].hash & mask;
        while (slots[t] != NIL)
            t = (t + 1) & mask;
        slots[t] = i;
    }
    free(c->slots);
    c->slots = slots;
    c->mask = mask;
}

/* Backward-shift deletion keeps probe chains intact without tombstones. */
static void index_remove_slot(Cache *c, size_t hole)
{
    size_t s = hole;
    for (;;) {
        s = (s + 1) & c->mask;
        uint32_t i = c->slots[s];
        if (i == NIL)
            break;
        size_t home = c->nodes[i].hash & c->mask;
        bool stays = hole <= s ? (hole < home && home <= s) : (hole < home || home <= s);
        if (!stays) {
            c->slots[hole] = i;
            hole = s;
        }
    }
    c->slots[hole] = NIL;
}

/* ---- node pool ---- */

static uint32_t node_alloc(Cache *c)
{
    if (c->free_head != NIL) {
        uint32_t i = c->free_head;
        c->free_head = c->nodes[i].next;
        return i;
    }
    if (c->nodes_len == c->nodes_cap) {
        c->nodes_cap *= 2;
        c->nodes = xrealloc(c->nodes, (size_t)c->nodes_cap * sizeof *c->nodes);
    }
    return c->nodes_len++;
}

static void node_release(Cache *c, uint32_t i)
{
    c->nodes[i].next = c->free_head;
    c->free_head = i;
}

/* ---- cache operations ---- */

static void cache_remove(Cache *c, size_t slot)
{
    uint32_t i = c->slots[slot];
    index_remove_slot(c, slot);
    list_unlink(c, i);
    node_release(c, i);
    c->size--;
}

static void cache_set(Cache *c, const char *key, uint32_t klen, const char *val, uint32_t vlen)
{
    uint64_t h = hash_bytes(key, klen);
    size_t s = index_find(c, key, klen, h);
    uint32_t i = c->slots[s];
    if (i != NIL) {
        c->nodes[i].val = val;
        c->nodes[i].vlen = vlen;
        list_touch(c, i);
        return;
    }

    i = node_alloc(c);
    c->nodes[i] = (Node){ .key = key, .val = val, .hash = h, .klen = klen, .vlen = vlen };
    c->slots[s] = i;
    list_push_front(c, i);
    c->size++;

    if (c->size > c->capacity) {
        const Node *lru = &c->nodes[c->tail];
        cache_remove(c, index_find(c, lru->key, lru->klen, lru->hash));
    }
    /* Keep the load factor at or below 1/2. */
    if ((size_t)c->size * 2 > c->mask + 1)
        index_grow(c);
}

static const Node *cache_get(Cache *c, const char *key, uint32_t klen)
{
    uint32_t i = c->slots[index_find(c, key, klen, hash_bytes(key, klen))];
    if (i == NIL)
        return NULL;
    list_touch(c, i);
    return &c->nodes[i];
}

static bool cache_del(Cache *c, const char *key, uint32_t klen)
{
    size_t s = index_find(c, key, klen, hash_bytes(key, klen));
    if (c->slots[s] == NIL)
        return false;
    cache_remove(c, s);
    return true;
}

/* ---- input parsing ---- */

typedef struct {
    const char *p;
    uint32_t len;
} Token;

/* Split line [p, end) on spaces into at most max tokens; returns the count,
 * or max + 1 if there are more. */
static size_t tokenize(const char *p, const char *end, Token *toks, size_t max)
{
    size_t n = 0;
    while (p < end) {
        if (*p == ' ') {
            p++;
            continue;
        }
        const char *start = p;
        while (p < end && *p != ' ')
            p++;
        if (n == max)
            return max + 1;
        toks[n++] = (Token){ start, (uint32_t)(p - start) };
    }
    return n;
}

static bool token_is(Token t, const char *word)
{
    size_t n = strlen(word);
    return t.len == n && memcmp(t.p, word, n) == 0;
}

/* Find the end of the line starting at p (excluding '\n' and a trailing '\r'),
 * and set *next to the start of the following line. */
static const char *line_end(const char *p, const char *end, const char **next)
{
    const char *nl = memchr(p, '\n', (size_t)(end - p));
    const char *e = nl ? nl : end;
    *next = nl ? nl + 1 : end;
    if (e > p && e[-1] == '\r')
        e--;
    return e;
}

static uint32_t parse_capacity(const char *p, const char *end)
{
    while (p < end && (*p == ' ' || *p == '\t'))
        p++;
    uint64_t v = 0;
    while (p < end && *p >= '0' && *p <= '9' && v <= UINT32_MAX)
        v = v * 10 + (uint64_t)(*p++ - '0');
    if (v < 1)
        v = 1;
    return v > UINT32_MAX - 1 ? UINT32_MAX - 1 : (uint32_t)v;
}

int cmd_lru(void)
{
    Input in = input_read_all(stdin);
    const char *p = in.data;
    const char *end = in.data + in.len;
    Output out;
    out_init(&out, stdout);

    if (p < end) {
        const char *next;
        const char *e = line_end(p, end, &next);
        Cache cache;
        cache_init(&cache, parse_capacity(p, e));
        p = next;

        while (p < end) {
            e = line_end(p, end, &next);
            Token t[3];
            size_t n = tokenize(p, e, t, 3);
            p = next;

            if (n == 3 && token_is(t[0], "SET")) {
                cache_set(&cache, t[1].p, t[1].len, t[2].p, t[2].len);
            } else if (n == 2 && token_is(t[0], "GET")) {
                const Node *node = cache_get(&cache, t[1].p, t[1].len);
                if (node)
                    out_write(&out, node->val, node->vlen);
                else
                    out_write(&out, "NULL", 4);
                out_char(&out, '\n');
            } else if (n == 2 && token_is(t[0], "DEL")) {
                out_char(&out, cache_del(&cache, t[1].p, t[1].len) ? '1' : '0');
                out_char(&out, '\n');
            } else if (n == 1 && token_is(t[0], "SIZE")) {
                out_u64(&out, cache.size);
                out_char(&out, '\n');
            }
            /* Anything else is not a valid command and is ignored. */
        }
        cache_free(&cache);
    }

    out_finish(&out);
    input_free(&in);
    return EXIT_SUCCESS;
}
