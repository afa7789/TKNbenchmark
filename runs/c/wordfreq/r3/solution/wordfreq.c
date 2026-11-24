/*
 * wordfreq: read stdin, print the 10 most frequent ASCII-letter words.
 *
 * A word is a maximal run of [A-Za-z], folded to lowercase. Output is
 * "<count> <word>" ordered by count descending, then word ascending.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TOP_N 10
#define READ_CHUNK (1u << 16)
#define INITIAL_TABLE_CAP (1u << 12) /* must be a power of two */

/* Growable byte buffer. */
typedef struct {
    char *data;
    size_t len;
    size_t cap;
} Buf;

/* One distinct word: its bytes live in the arena at [off, off + len). */
typedef struct {
    uint64_t hash;
    size_t off;
    size_t len;
    uint64_t count; /* 0 marks an empty slot */
} Entry;

typedef struct {
    Entry *slots;
    size_t cap; /* power of two */
    size_t used;
    Buf arena; /* concatenated bytes of all distinct words */
} Table;

static void die_oom(void)
{
    fputs("wordfreq: out of memory\n", stderr);
    exit(EXIT_FAILURE);
}

static void buf_reserve(Buf *b, size_t extra)
{
    if (b->cap - b->len >= extra)
        return;
    size_t need = b->len + extra;
    if (need < b->len)
        die_oom();
    size_t cap = b->cap ? b->cap : 64;
    while (cap < need) {
        if (cap > SIZE_MAX / 2)
            die_oom();
        cap *= 2;
    }
    char *p = realloc(b->data, cap);
    if (!p)
        die_oom();
    b->data = p;
    b->cap = cap;
}

static void buf_append(Buf *b, const char *src, size_t n)
{
    buf_reserve(b, n);
    memcpy(b->data + b->len, src, n);
    b->len += n;
}

/* FNV-1a, 64-bit. */
static uint64_t hash_bytes(const char *s, size_t n)
{
    uint64_t h = 0xcbf29ce484222325u;
    for (size_t i = 0; i < n; i++) {
        h ^= (unsigned char)s[i];
        h *= 0x100000001b3u;
    }
    return h;
}

static void table_init(Table *t)
{
    t->cap = INITIAL_TABLE_CAP;
    t->used = 0;
    t->slots = calloc(t->cap, sizeof *t->slots);
    if (!t->slots)
        die_oom();
    t->arena = (Buf){0};
}

static void table_free(Table *t)
{
    free(t->slots);
    free(t->arena.data);
    *t = (Table){0};
}

static void table_grow(Table *t)
{
    if (t->cap > SIZE_MAX / 2 / sizeof *t->slots)
        die_oom();
    size_t cap = t->cap * 2;
    Entry *slots = calloc(cap, sizeof *slots);
    if (!slots)
        die_oom();
    size_t mask = cap - 1;
    for (size_t i = 0; i < t->cap; i++) {
        const Entry *e = &t->slots[i];
        if (!e->count)
            continue;
        size_t j = (size_t)e->hash & mask;
        while (slots[j].count)
            j = (j + 1) & mask;
        slots[j] = *e;
    }
    free(t->slots);
    t->slots = slots;
    t->cap = cap;
}

/* Count one occurrence of the lowercase word w[0..n). */
static void table_add(Table *t, const char *w, size_t n)
{
    uint64_t h = hash_bytes(w, n);
    size_t mask = t->cap - 1;
    size_t i = (size_t)h & mask;
    for (;;) {
        Entry *e = &t->slots[i];
        if (!e->count)
            break;
        if (e->hash == h && e->len == n &&
            memcmp(t->arena.data + e->off, w, n) == 0) {
            e->count++;
            return;
        }
        i = (i + 1) & mask;
    }

    /* New word: keep load factor at or below 1/2. */
    if ((t->used + 1) * 2 > t->cap) {
        table_grow(t);
        mask = t->cap - 1;
        i = (size_t)h & mask;
        while (t->slots[i].count)
            i = (i + 1) & mask;
    }
    size_t off = t->arena.len;
    buf_append(&t->arena, w, n);
    t->slots[i] = (Entry){.hash = h, .off = off, .len = n, .count = 1};
    t->used++;
}

/* Byte-order comparison of two words. */
static int word_cmp(const Table *t, const Entry *a, const Entry *b)
{
    size_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(t->arena.data + a->off, t->arena.data + b->off, n);
    if (c)
        return c;
    return (a->len > b->len) - (a->len < b->len);
}

/* True if a should be printed before b. */
static bool ranks_before(const Table *t, const Entry *a, const Entry *b)
{
    if (a->count != b->count)
        return a->count > b->count;
    return word_cmp(t, a, b) < 0;
}

static inline bool is_alpha(unsigned char c)
{
    return (unsigned char)((c | 0x20) - 'a') < 26;
}

int main(void)
{
    Table t;
    table_init(&t);
    Buf word = {0}; /* current word, possibly spanning read chunks */

    static char chunk[READ_CHUNK];
    size_t got;
    while ((got = fread(chunk, 1, sizeof chunk, stdin)) > 0) {
        size_t i = 0;
        while (i < got) {
            if (!is_alpha((unsigned char)chunk[i])) {
                if (word.len) {
                    table_add(&t, word.data, word.len);
                    word.len = 0;
                }
                i++;
                continue;
            }
            size_t start = i;
            while (i < got && is_alpha((unsigned char)chunk[i])) {
                chunk[i] |= 0x20; /* ASCII letter to lowercase */
                i++;
            }
            if (i < got && word.len == 0) {
                /* Word lies entirely inside this chunk: no copy needed. */
                table_add(&t, chunk + start, i - start);
            } else {
                buf_append(&word, chunk + start, i - start);
            }
        }
    }
    if (ferror(stdin)) {
        perror("wordfreq: read error");
        free(word.data);
        table_free(&t);
        return EXIT_FAILURE;
    }
    if (word.len)
        table_add(&t, word.data, word.len);
    free(word.data);

    /* Select the top N with a small insertion-sorted array. */
    const Entry *top[TOP_N];
    size_t ntop = 0;
    for (size_t i = 0; i < t.cap; i++) {
        const Entry *e = &t.slots[i];
        if (!e->count)
            continue;
        if (ntop == TOP_N && !ranks_before(&t, e, top[TOP_N - 1]))
            continue;
        size_t j = ntop < TOP_N ? ntop++ : TOP_N - 1;
        while (j > 0 && ranks_before(&t, e, top[j - 1])) {
            top[j] = top[j - 1];
            j--;
        }
        top[j] = e;
    }

    for (size_t i = 0; i < ntop; i++) {
        printf("%llu %.*s\n", (unsigned long long)top[i]->count,
               (int)top[i]->len, t.arena.data + top[i]->off);
    }

    table_free(&t);
    return fflush(stdout) == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
