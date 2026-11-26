/*
 * lru: an LRU cache simulator.
 *
 * Entries live in a growable node pool and are threaded on a doubly linked
 * recency list (head = most recent). A linear-probing hash table of node
 * indices, with backward-shift deletion, gives O(1) expected lookups.
 */
#include "commands.h"
#include "util.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    MAX_TOKEN = 64,
    MAX_CAPACITY = 1000000,
    POOL_INITIAL = 1024,
};

#define NIL UINT32_MAX

typedef struct {
    uint64_t hash;
    uint32_t prev;
    uint32_t next;
    uint8_t key_len;
    uint8_t val_len;
    char key[MAX_TOKEN];
    char val[MAX_TOKEN];
} Node;

typedef struct {
    size_t capacity; /* maximum number of keys held */
    size_t size;

    Node *nodes;
    uint32_t pool_len; /* nodes ever handed out */
    uint32_t pool_cap;
    uint32_t free_list; /* chained through `next` */

    uint32_t head; /* most recently used */
    uint32_t tail; /* least recently used */

    uint32_t *slots; /* node indices, NIL when empty */
    size_t slot_mask;
} Cache;

typedef struct {
    const char *ptr;
    size_t len;
} Token;

static void cache_init(Cache *c, size_t capacity)
{
    c->capacity = capacity;
    c->size = 0;
    c->pool_cap = POOL_INITIAL;
    c->nodes = xmalloc(sizeof(Node) * c->pool_cap);
    c->pool_len = 0;
    c->free_list = NIL;
    c->head = c->tail = NIL;
    size_t nslots = 2 * (size_t)POOL_INITIAL;
    c->slots = xmalloc(sizeof(uint32_t) * nslots);
    memset(c->slots, 0xff, sizeof(uint32_t) * nslots);
    c->slot_mask = nslots - 1;
}

static void cache_free(Cache *c)
{
    free(c->nodes);
    free(c->slots);
}

/* ---- hash index ---- */

static size_t index_find(const Cache *c, Token key, uint64_t hash)
{
    size_t i = hash & c->slot_mask;
    for (;;) {
        uint32_t n = c->slots[i];
        if (n == NIL)
            return i;
        const Node *node = &c->nodes[n];
        if (node->hash == hash && node->key_len == key.len && memcmp(node->key, key.ptr, key.len) == 0)
            return i;
        i = (i + 1) & c->slot_mask;
    }
}

static void index_insert_node(uint32_t *slots, size_t mask, const Node *nodes, uint32_t n)
{
    size_t i = nodes[n].hash & mask;
    while (slots[i] != NIL)
        i = (i + 1) & mask;
    slots[i] = n;
}

static void index_rebuild(Cache *c, size_t nslots)
{
    free(c->slots);
    c->slots = xmalloc(sizeof(uint32_t) * nslots);
    memset(c->slots, 0xff, sizeof(uint32_t) * nslots);
    c->slot_mask = nslots - 1;
    for (uint32_t n = c->head; n != NIL; n = c->nodes[n].next)
        index_insert_node(c->slots, c->slot_mask, c->nodes, n);
}

/* Remove the entry in slot i, shifting later probe-chain members back. */
static void index_remove_at(Cache *c, size_t i)
{
    size_t mask = c->slot_mask;
    size_t j = i;
    for (;;) {
        j = (j + 1) & mask;
        uint32_t n = c->slots[j];
        if (n == NIL)
            break;
        size_t home = c->nodes[n].hash & mask;
        /* Move n into the hole unless its home lies cyclically in (i, j]. */
        bool stays = i <= j ? (i < home && home <= j) : (i < home || home <= j);
        if (!stays) {
            c->slots[i] = n;
            i = j;
        }
    }
    c->slots[i] = NIL;
}

/* ---- recency list ---- */

static void list_unlink(Cache *c, uint32_t n)
{
    Node *node = &c->nodes[n];
    if (node->prev != NIL)
        c->nodes[node->prev].next = node->next;
    else
        c->head = node->next;
    if (node->next != NIL)
        c->nodes[node->next].prev = node->prev;
    else
        c->tail = node->prev;
}

static void list_push_front(Cache *c, uint32_t n)
{
    Node *node = &c->nodes[n];
    node->prev = NIL;
    node->next = c->head;
    if (c->head != NIL)
        c->nodes[c->head].prev = n;
    else
        c->tail = n;
    c->head = n;
}

static void touch(Cache *c, uint32_t n)
{
    if (c->head != n) {
        list_unlink(c, n);
        list_push_front(c, n);
    }
}

/* ---- node pool ---- */

static uint32_t node_alloc(Cache *c)
{
    if (c->free_list != NIL) {
        uint32_t n = c->free_list;
        c->free_list = c->nodes[n].next;
        return n;
    }
    if (c->pool_len == c->pool_cap) {
        c->pool_cap *= 2;
        c->nodes = xrealloc(c->nodes, sizeof(Node) * c->pool_cap);
    }
    return c->pool_len++;
}

static void node_release(Cache *c, uint32_t n)
{
    c->nodes[n].next = c->free_list;
    c->free_list = n;
}

/* Unlink, unindex and release the entry whose index slot is `slot`. */
static void remove_entry(Cache *c, size_t slot)
{
    uint32_t n = c->slots[slot];
    index_remove_at(c, slot);
    list_unlink(c, n);
    node_release(c, n);
    c->size--;
}

/* ---- commands ---- */

static void cache_set(Cache *c, Token key, Token val)
{
    uint64_t hash = hash_bytes(key.ptr, key.len);
    size_t slot = index_find(c, key, hash);
    uint32_t n = c->slots[slot];
    if (n != NIL) {
        Node *node = &c->nodes[n];
        memcpy(node->val, val.ptr, val.len);
        node->val_len = (uint8_t)val.len;
        touch(c, n);
        return;
    }

    if (c->size == c->capacity) {
        /* Evicting first is equivalent to inserting then evicting: the
         * victim is never the new key. */
        const Node *victim = &c->nodes[c->tail];
        Token vkey = {victim->key, victim->key_len};
        remove_entry(c, index_find(c, vkey, victim->hash));
        slot = index_find(c, key, hash);
    }

    n = node_alloc(c);
    Node *node = &c->nodes[n];
    node->hash = hash;
    node->key_len = (uint8_t)key.len;
    node->val_len = (uint8_t)val.len;
    memcpy(node->key, key.ptr, key.len);
    memcpy(node->val, val.ptr, val.len);
    list_push_front(c, n);
    c->slots[slot] = n;
    c->size++;

    if (c->size * 2 > c->slot_mask + 1)
        index_rebuild(c, (c->slot_mask + 1) * 2);
}

static void cache_get(Cache *c, Token key)
{
    size_t slot = index_find(c, key, hash_bytes(key.ptr, key.len));
    uint32_t n = c->slots[slot];
    if (n == NIL) {
        fputs("NULL\n", stdout);
        return;
    }
    touch(c, n);
    const Node *node = &c->nodes[n];
    fwrite(node->val, 1, node->val_len, stdout);
    putchar('\n');
}

static void cache_del(Cache *c, Token key)
{
    size_t slot = index_find(c, key, hash_bytes(key.ptr, key.len));
    if (c->slots[slot] == NIL) {
        fputs("0\n", stdout);
        return;
    }
    remove_entry(c, slot);
    fputs("1\n", stdout);
}

/* ---- parsing ---- */

static bool valid_token(Token t)
{
    return t.len >= 1 && t.len <= MAX_TOKEN;
}

/* Split `s` at its first space into head and tail (tail empty if none). */
static void split(Token s, Token *head, Token *tail)
{
    const char *sp = memchr(s.ptr, ' ', s.len);
    if (!sp) {
        *head = s;
        *tail = (Token){s.ptr + s.len, 0};
        return;
    }
    size_t n = (size_t)(sp - s.ptr);
    *head = (Token){s.ptr, n};
    *tail = (Token){sp + 1, s.len - n - 1};
}

static bool token_is(Token t, const char *word)
{
    size_t n = strlen(word);
    return t.len == n && memcmp(t.ptr, word, n) == 0;
}

static bool parse_capacity(Token t, size_t *out)
{
    size_t v = 0;
    size_t i = 0;
    while (i < t.len && (t.ptr[i] == ' ' || t.ptr[i] == '\t'))
        i++;
    size_t digits = 0;
    for (; i < t.len && t.ptr[i] >= '0' && t.ptr[i] <= '9'; i++, digits++) {
        v = v * 10 + (size_t)(t.ptr[i] - '0');
        if (v > MAX_CAPACITY)
            return false;
    }
    while (i < t.len && (t.ptr[i] == ' ' || t.ptr[i] == '\t'))
        i++;
    if (digits == 0 || i != t.len || v < 1)
        return false;
    *out = v;
    return true;
}

/* Malformed command lines are ignored. */
static void run_command(Cache *c, Token line)
{
    Token cmd, rest, key, val, extra;
    split(line, &cmd, &rest);
    if (token_is(cmd, "SET")) {
        split(rest, &key, &val);
        if (valid_token(key) && valid_token(val) && !memchr(val.ptr, ' ', val.len))
            cache_set(c, key, val);
    } else if (token_is(cmd, "GET")) {
        split(rest, &key, &extra);
        if (valid_token(key) && extra.len == 0)
            cache_get(c, key);
    } else if (token_is(cmd, "DEL")) {
        split(rest, &key, &extra);
        if (valid_token(key) && extra.len == 0)
            cache_del(c, key);
    } else if (token_is(cmd, "SIZE") && rest.len == 0 && line.len == 4) {
        printf("%zu\n", c->size);
    }
}

static Token line_token(const char *s, size_t len)
{
    if (len > 0 && s[len - 1] == '\r')
        len--;
    return (Token){s, len};
}

int cmd_lru(void)
{
    LineReader lr;
    line_reader_init(&lr, stdin);

    const char *s;
    size_t len;
    size_t capacity;
    if (!line_reader_next(&lr, &s, &len) || !parse_capacity(line_token(s, len), &capacity)) {
        line_reader_free(&lr);
        return 0;
    }

    Cache cache;
    cache_init(&cache, capacity);
    while (line_reader_next(&lr, &s, &len))
        run_command(&cache, line_token(s, len));

    cache_free(&cache);
    line_reader_free(&lr);
    return 0;
}
