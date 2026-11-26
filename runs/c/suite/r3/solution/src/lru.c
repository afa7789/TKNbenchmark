/*
 * lru: an LRU cache simulator.
 *
 * Entries live in a growable node pool and are addressed by index. A
 * doubly linked list orders them from most (head) to least (tail) recently
 * used, and a chained hash table maps keys to nodes. Every command runs in
 * O(1) expected time.
 */
#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "commands.h"
#include "util.h"

#define MAX_TOKEN 64
#define MAX_CAPACITY 1000000
#define NIL UINT32_MAX
#define INITIAL_BUCKETS ((uint32_t)1 << 10)
#define INITIAL_NODES ((uint32_t)1 << 10)

typedef struct {
    uint32_t prev;  /* towards the most recently used end */
    uint32_t next;  /* towards the least recently used end */
    uint32_t chain; /* next node in the same hash bucket, or free list link */
    uint32_t hash;
    uint8_t key_len;
    uint8_t val_len;
    char key[MAX_TOKEN];
    char val[MAX_TOKEN];
} Node;

typedef struct {
    Node *nodes;
    uint32_t nodes_cap;
    uint32_t nodes_len; /* nodes ever handed out from the pool */
    uint32_t free_head;
    uint32_t *buckets;
    uint32_t bucket_mask;
    uint32_t size;
    uint32_t capacity;
    uint32_t head;
    uint32_t tail;
} Lru;

typedef struct {
    const char *ptr;
    size_t len;
} Token;

static uint32_t hash_key(const char *key, size_t len)
{
    uint32_t h = UINT32_C(2166136261);
    for (size_t i = 0; i < len; i++)
        h = (h ^ (unsigned char)key[i]) * UINT32_C(16777619);
    return h;
}

static void lru_init(Lru *c, uint32_t capacity)
{
    c->capacity = capacity;
    c->nodes_cap = capacity < INITIAL_NODES ? capacity : INITIAL_NODES;
    c->nodes = xmalloc((size_t)c->nodes_cap * sizeof *c->nodes);
    c->nodes_len = 0;
    c->free_head = NIL;
    c->bucket_mask = INITIAL_BUCKETS - 1;
    c->buckets = xmalloc((size_t)INITIAL_BUCKETS * sizeof *c->buckets);
    for (uint32_t i = 0; i < INITIAL_BUCKETS; i++)
        c->buckets[i] = NIL;
    c->size = 0;
    c->head = c->tail = NIL;
}

static void lru_free(Lru *c)
{
    free(c->nodes);
    free(c->buckets);
}

/* ---- recency list ---- */

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

/* ---- hash index ---- */

static uint32_t index_find(const Lru *c, const char *key, size_t len, uint32_t hash)
{
    for (uint32_t i = c->buckets[hash & c->bucket_mask]; i != NIL; i = c->nodes[i].chain) {
        const Node *n = &c->nodes[i];
        if (n->hash == hash && n->key_len == len && memcmp(n->key, key, len) == 0)
            return i;
    }
    return NIL;
}

static void index_insert(Lru *c, uint32_t i)
{
    uint32_t *bucket = &c->buckets[c->nodes[i].hash & c->bucket_mask];
    c->nodes[i].chain = *bucket;
    *bucket = i;
}

static void index_remove(Lru *c, uint32_t i)
{
    uint32_t *link = &c->buckets[c->nodes[i].hash & c->bucket_mask];
    while (*link != i)
        link = &c->nodes[*link].chain;
    *link = c->nodes[i].chain;
}

static void index_grow(Lru *c)
{
    uint32_t count = (c->bucket_mask + 1) * 2;
    free(c->buckets);
    c->buckets = xmalloc((size_t)count * sizeof *c->buckets);
    c->bucket_mask = count - 1;
    for (uint32_t i = 0; i < count; i++)
        c->buckets[i] = NIL;
    for (uint32_t i = c->head; i != NIL; i = c->nodes[i].next)
        index_insert(c, i);
}

/* ---- node pool ---- */

static uint32_t node_alloc(Lru *c)
{
    if (c->free_head != NIL) {
        uint32_t i = c->free_head;
        c->free_head = c->nodes[i].chain;
        return i;
    }
    if (c->nodes_len == c->nodes_cap) {
        uint32_t cap = c->nodes_cap * 2;
        if (cap > c->capacity)
            cap = c->capacity;
        c->nodes = xrealloc(c->nodes, (size_t)cap * sizeof *c->nodes);
        c->nodes_cap = cap;
    }
    return c->nodes_len++;
}

static void node_release(Lru *c, uint32_t i)
{
    c->nodes[i].chain = c->free_head;
    c->free_head = i;
}

/* Detach node `i` from the index and the list and return it to the pool. */
static void lru_remove(Lru *c, uint32_t i)
{
    index_remove(c, i);
    list_unlink(c, i);
    node_release(c, i);
    c->size--;
}

/* ---- commands ---- */

static void lru_set(Lru *c, Token key, Token val)
{
    uint32_t hash = hash_key(key.ptr, key.len);
    uint32_t i = index_find(c, key.ptr, key.len, hash);

    if (i == NIL) {
        if (c->size == c->capacity)
            lru_remove(c, c->tail);
        i = node_alloc(c);
        Node *n = &c->nodes[i];
        n->hash = hash;
        n->key_len = (uint8_t)key.len;
        memcpy(n->key, key.ptr, key.len);
        index_insert(c, i);
        list_push_front(c, i);
        if (++c->size > c->bucket_mask + 1)
            index_grow(c);
    } else {
        list_touch(c, i);
    }

    Node *n = &c->nodes[i];
    n->val_len = (uint8_t)val.len;
    memcpy(n->val, val.ptr, val.len);
}

static void lru_get(Lru *c, Token key, FILE *out)
{
    uint32_t i = key.len <= MAX_TOKEN ? index_find(c, key.ptr, key.len, hash_key(key.ptr, key.len)) : NIL;
    if (i == NIL) {
        fputs("NULL\n", out);
        return;
    }
    list_touch(c, i);
    fwrite(c->nodes[i].val, 1, c->nodes[i].val_len, out);
    fputc('\n', out);
}

static void lru_del(Lru *c, Token key, FILE *out)
{
    uint32_t i = key.len <= MAX_TOKEN ? index_find(c, key.ptr, key.len, hash_key(key.ptr, key.len)) : NIL;
    if (i != NIL)
        lru_remove(c, i);
    fputs(i != NIL ? "1\n" : "0\n", out);
}

/* ---- input parsing ---- */

/* Split `line` on spaces into at most `max` tokens; returns the token count. */
static size_t tokenize(const char *line, size_t len, Token *tokens, size_t max)
{
    size_t count = 0;
    size_t i = 0;

    while (i < len && count < max) {
        while (i < len && line[i] == ' ')
            i++;
        if (i == len)
            break;
        size_t start = i;
        while (i < len && line[i] != ' ')
            i++;
        tokens[count++] = (Token){ line + start, i - start };
    }
    return count;
}

static bool token_is(Token t, const char *word)
{
    size_t n = strlen(word);
    return t.len == n && memcmp(t.ptr, word, n) == 0;
}

static bool parse_capacity(const char *line, size_t len, uint32_t *capacity)
{
    uint64_t value = 0;
    size_t i = 0;

    while (i < len && (line[i] == ' ' || line[i] == '\t'))
        i++;
    size_t digits_start = i;
    while (i < len && line[i] >= '0' && line[i] <= '9') {
        value = value * 10 + (uint64_t)(line[i] - '0');
        if (value > MAX_CAPACITY)
            return false;
        i++;
    }
    while (i < len && (line[i] == ' ' || line[i] == '\t' || line[i] == '\r'))
        i++;
    if (i == digits_start || i != len || value < 1)
        return false;
    *capacity = (uint32_t)value;
    return true;
}

int cmd_lru(FILE *in, FILE *out)
{
    LineReader reader;
    line_reader_init(&reader, in);

    const char *line;
    size_t len;
    uint32_t capacity;

    if (!line_reader_next(&reader, &line, &len)) {
        line_reader_free(&reader);
        return 0;
    }
    if (!parse_capacity(line, len, &capacity)) {
        fputs("app: lru: invalid capacity\n", stderr);
        line_reader_free(&reader);
        return 0;
    }

    Lru cache;
    lru_init(&cache, capacity);

    while (line_reader_next(&reader, &line, &len)) {
        if (len > 0 && line[len - 1] == '\r')
            len--;

        Token tok[3];
        size_t n = tokenize(line, len, tok, 3);
        if (n == 0)
            continue;

        if (token_is(tok[0], "SET") && n >= 3) {
            if (tok[1].len <= MAX_TOKEN && tok[2].len <= MAX_TOKEN)
                lru_set(&cache, tok[1], tok[2]);
        } else if (token_is(tok[0], "GET") && n >= 2) {
            lru_get(&cache, tok[1], out);
        } else if (token_is(tok[0], "DEL") && n >= 2) {
            lru_del(&cache, tok[1], out);
        } else if (token_is(tok[0], "SIZE")) {
            fprintf(out, "%" PRIu32 "\n", cache.size);
        }
    }

    lru_free(&cache);
    line_reader_free(&reader);
    return 0;
}
