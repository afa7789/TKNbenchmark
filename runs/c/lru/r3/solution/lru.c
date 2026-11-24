/*
 * lru — simulate an LRU cache driven by commands on standard input.
 *
 * The whole input is read into memory once; keys and values are stored as
 * (pointer, length) slices into that buffer, so no per-entry allocation is
 * needed. Entries live in a preallocated node pool linked into an intrusive
 * doubly linked recency list and a chained hash table, giving O(1) expected
 * time per command.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NIL UINT32_MAX

typedef struct {
    const char *key;
    const char *val;
    uint32_t    hash;
    uint32_t    prev;   /* towards more recently used */
    uint32_t    next;   /* towards less recently used */
    uint32_t    chain;  /* next node in the same hash bucket, or free list */
    uint8_t     klen;
    uint8_t     vlen;
} Node;

typedef struct {
    Node     *nodes;
    uint32_t *buckets;
    uint32_t  mask;
    uint32_t  capacity;
    uint32_t  size;
    uint32_t  used;      /* nodes ever handed out from the pool */
    uint32_t  free_head; /* recycled nodes */
    uint32_t  head;      /* most recently used */
    uint32_t  tail;      /* least recently used */
} Cache;

typedef struct {
    char  *data;
    size_t len;
    size_t cap;
} Buf;

static _Noreturn void die(const char *msg)
{
    fprintf(stderr, "lru: %s\n", msg);
    exit(EXIT_FAILURE);
}

static void *xmalloc(size_t n)
{
    void *p = malloc(n ? n : 1);
    if (!p)
        die("out of memory");
    return p;
}

static void buf_reserve(Buf *b, size_t extra)
{
    if (b->cap - b->len >= extra)
        return;
    size_t cap = b->cap ? b->cap : 1 << 16;
    while (cap - b->len < extra)
        cap *= 2;
    char *p = realloc(b->data, cap);
    if (!p)
        die("out of memory");
    b->data = p;
    b->cap = cap;
}

static Buf read_all(FILE *in)
{
    Buf b = {0};
    for (;;) {
        buf_reserve(&b, 1 << 16);
        size_t n = fread(b.data + b.len, 1, b.cap - b.len, in);
        b.len += n;
        if (n == 0) {
            if (ferror(in))
                die("read error");
            break;
        }
    }
    return b;
}

/* FNV-1a */
static uint32_t hash_bytes(const char *s, size_t n)
{
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++) {
        h ^= (unsigned char)s[i];
        h *= 16777619u;
    }
    return h ^ (h >> 15);
}

static void cache_init(Cache *c, uint32_t capacity, uint32_t max_nodes)
{
    size_t nb = 16;
    while (nb < (size_t)max_nodes * 2)
        nb <<= 1;

    c->nodes = xmalloc((size_t)max_nodes * sizeof *c->nodes);
    c->buckets = xmalloc(nb * sizeof *c->buckets);
    memset(c->buckets, 0xff, nb * sizeof *c->buckets); /* all NIL */
    c->mask = (uint32_t)(nb - 1);
    c->capacity = capacity;
    c->size = 0;
    c->used = 0;
    c->free_head = NIL;
    c->head = c->tail = NIL;
}

static void cache_free(Cache *c)
{
    free(c->nodes);
    free(c->buckets);
}

/* Returns the node index for key, or NIL. If pslot is given, it receives the
 * address of the link pointing at the found node (for unlinking). */
static uint32_t cache_find(const Cache *c, const char *key, size_t klen,
                           uint32_t h, uint32_t **pslot)
{
    uint32_t *slot = &c->buckets[h & c->mask];
    while (*slot != NIL) {
        const Node *n = &c->nodes[*slot];
        if (n->hash == h && n->klen == klen && memcmp(n->key, key, klen) == 0) {
            if (pslot)
                *pslot = slot;
            return *slot;
        }
        slot = &c->nodes[*slot].chain;
    }
    return NIL;
}

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

static void touch(Cache *c, uint32_t i)
{
    if (c->head == i)
        return;
    list_unlink(c, i);
    list_push_front(c, i);
}

/* Remove node i, given the hash-chain link that points at it. */
static void remove_node(Cache *c, uint32_t i, uint32_t *slot)
{
    *slot = c->nodes[i].chain;
    list_unlink(c, i);
    c->nodes[i].chain = c->free_head;
    c->free_head = i;
    c->size--;
}

static void remove_key(Cache *c, const char *key, size_t klen, uint32_t h)
{
    uint32_t *slot;
    uint32_t i = cache_find(c, key, klen, h, &slot);
    if (i != NIL)
        remove_node(c, i, slot);
}

static const Node *cache_get(Cache *c, const char *key, size_t klen)
{
    uint32_t i = cache_find(c, key, klen, hash_bytes(key, klen), NULL);
    if (i == NIL)
        return NULL;
    touch(c, i);
    return &c->nodes[i];
}

static int cache_del(Cache *c, const char *key, size_t klen)
{
    uint32_t *slot;
    uint32_t i = cache_find(c, key, klen, hash_bytes(key, klen), &slot);
    if (i == NIL)
        return 0;
    remove_node(c, i, slot);
    return 1;
}

static void cache_set(Cache *c, const char *key, size_t klen,
                      const char *val, size_t vlen)
{
    uint32_t h = hash_bytes(key, klen);
    uint32_t i = cache_find(c, key, klen, h, NULL);
    if (i != NIL) {
        c->nodes[i].val = val;
        c->nodes[i].vlen = (uint8_t)vlen;
        touch(c, i);
        return;
    }

    if (c->size == c->capacity) {
        const Node *lru = &c->nodes[c->tail];
        remove_key(c, lru->key, lru->klen, lru->hash);
    }

    if (c->free_head != NIL) {
        i = c->free_head;
        c->free_head = c->nodes[i].chain;
    } else {
        i = c->used++;
    }

    Node *n = &c->nodes[i];
    n->key = key;
    n->klen = (uint8_t)klen;
    n->val = val;
    n->vlen = (uint8_t)vlen;
    n->hash = h;
    uint32_t *bucket = &c->buckets[h & c->mask];
    n->chain = *bucket;
    *bucket = i;
    list_push_front(c, i);
    c->size++;
}

static void out_bytes(Buf *out, const char *s, size_t n)
{
    buf_reserve(out, n + 1);
    memcpy(out->data + out->len, s, n);
    out->len += n;
    out->data[out->len++] = '\n';
}

static void out_uint(Buf *out, uint32_t v)
{
    char tmp[16];
    size_t n = 0;
    do {
        tmp[sizeof tmp - 1 - n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    out_bytes(out, tmp + sizeof tmp - n, n);
}

/* Split the next space-delimited token from [*p, end). */
static int next_token(const char **p, const char *end, const char **tok, size_t *len)
{
    const char *s = *p;
    while (s < end && *s == ' ')
        s++;
    const char *e = s;
    while (e < end && *e != ' ')
        e++;
    *tok = s;
    *len = (size_t)(e - s);
    *p = e;
    return e > s;
}

static void run_command(Cache *c, Buf *out, const char *line, const char *end)
{
    const char *cmd, *key, *val;
    size_t cmdlen, klen, vlen;

    if (!next_token(&line, end, &cmd, &cmdlen))
        return;

    if (cmdlen == 4 && memcmp(cmd, "SIZE", 4) == 0) {
        out_uint(out, c->size);
        return;
    }
    if (cmdlen != 3 || !next_token(&line, end, &key, &klen) || klen > UINT8_MAX)
        return;

    if (memcmp(cmd, "GET", 3) == 0) {
        const Node *n = cache_get(c, key, klen);
        if (n)
            out_bytes(out, n->val, n->vlen);
        else
            out_bytes(out, "NULL", 4);
    } else if (memcmp(cmd, "DEL", 3) == 0) {
        out_bytes(out, cache_del(c, key, klen) ? "1" : "0", 1);
    } else if (memcmp(cmd, "SET", 3) == 0) {
        if (next_token(&line, end, &val, &vlen) && vlen <= UINT8_MAX)
            cache_set(c, key, klen, val, vlen);
    }
}

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
    Buf in = read_all(stdin);
    const char *p = in.data;
    const char *end = in.data + in.len;

    if (p == end)
        return EXIT_SUCCESS;

    const char *next;
    const char *e = line_end(p, end, &next);
    char first[32] = {0};
    size_t flen = (size_t)(e - p) < sizeof first - 1 ? (size_t)(e - p) : sizeof first - 1;
    memcpy(first, p, flen);
    long cap = strtol(first, NULL, 10);
    if (cap < 1)
        cap = 1;
    if (cap > 1000000)
        cap = 1000000;
    p = next;

    /* The pool never needs more nodes than the capacity or the number of
     * remaining lines, whichever is smaller. */
    size_t lines = 0;
    for (const char *q = p; q < end && (q = memchr(q, '\n', (size_t)(end - q))); q++)
        lines++;
    lines++;
    uint32_t max_nodes = (uint32_t)((size_t)cap < lines ? (size_t)cap : lines);

    Cache cache;
    cache_init(&cache, (uint32_t)cap, max_nodes);
    Buf out = {0};

    while (p < end) {
        e = line_end(p, end, &next);
        run_command(&cache, &out, p, e);
        p = next;
    }

    if (out.len && fwrite(out.data, 1, out.len, stdout) != out.len)
        die("write error");
    if (fflush(stdout) != 0)
        die("write error");

    cache_free(&cache);
    free(out.data);
    free(in.data);
    return EXIT_SUCCESS;
}
