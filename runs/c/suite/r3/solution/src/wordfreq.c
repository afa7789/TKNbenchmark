/*
 * wordfreq: count case-folded runs of ASCII letters and print the ten most
 * frequent, ordered by count descending, then word ascending (byte order).
 */
#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "commands.h"
#include "util.h"

#define TOP_N 10
#define READ_CHUNK ((size_t)1 << 16)
#define TABLE_INITIAL_SLOTS ((size_t)1 << 12)

#define FNV64_OFFSET UINT64_C(0xcbf29ce484222325)
#define FNV64_PRIME UINT64_C(0x100000001b3)

/* A slot is empty when count == 0. Word bytes live in the table's arena. */
typedef struct {
    uint64_t hash;
    size_t off;
    size_t len;
    uint64_t count;
} WordEntry;

typedef struct {
    WordEntry *slots;
    size_t mask; /* slot count - 1; slot count is a power of two */
    size_t used;
    char *arena;
    size_t arena_len;
    size_t arena_cap;
} WordTable;

static void table_init(WordTable *t)
{
    t->slots = xcalloc(TABLE_INITIAL_SLOTS, sizeof *t->slots);
    t->mask = TABLE_INITIAL_SLOTS - 1;
    t->used = 0;
    t->arena_cap = (size_t)1 << 16;
    t->arena = xmalloc(t->arena_cap);
    t->arena_len = 0;
}

static void table_free(WordTable *t)
{
    free(t->slots);
    free(t->arena);
}

static void table_grow(WordTable *t)
{
    size_t new_slots = (t->mask + 1) * 2;
    size_t new_mask = new_slots - 1;
    WordEntry *slots = xcalloc(new_slots, sizeof *slots);

    for (size_t i = 0; i <= t->mask; i++) {
        const WordEntry *e = &t->slots[i];
        if (e->count == 0)
            continue;
        size_t j = (size_t)e->hash & new_mask;
        while (slots[j].count != 0)
            j = (j + 1) & new_mask;
        slots[j] = *e;
    }
    free(t->slots);
    t->slots = slots;
    t->mask = new_mask;
}

static size_t arena_store(WordTable *t, const char *word, size_t len)
{
    if (t->arena_cap - t->arena_len < len) {
        size_t cap = t->arena_cap;
        while (cap - t->arena_len < len)
            cap *= 2;
        t->arena = xrealloc(t->arena, cap);
        t->arena_cap = cap;
    }
    size_t off = t->arena_len;
    memcpy(t->arena + off, word, len);
    t->arena_len += len;
    return off;
}

static void table_add(WordTable *t, const char *word, size_t len, uint64_t hash)
{
    size_t i = (size_t)hash & t->mask;

    for (;;) {
        WordEntry *e = &t->slots[i];
        if (e->count == 0)
            break;
        if (e->hash == hash && e->len == len && memcmp(t->arena + e->off, word, len) == 0) {
            e->count++;
            return;
        }
        i = (i + 1) & t->mask;
    }

    WordEntry *e = &t->slots[i];
    e->hash = hash;
    e->off = arena_store(t, word, len);
    e->len = len;
    e->count = 1;

    /* Keep the load factor at or below 1/2 for short probe sequences. */
    if (++t->used * 2 > t->mask + 1)
        table_grow(t);
}

/* True if `a` ranks strictly before `b` in the output order. */
static bool ranks_before(const WordTable *t, const WordEntry *a, const WordEntry *b)
{
    if (a->count != b->count)
        return a->count > b->count;
    size_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(t->arena + a->off, t->arena + b->off, n);
    if (c != 0)
        return c < 0;
    return a->len < b->len;
}

static void print_top(const WordTable *t, FILE *out)
{
    const WordEntry *top[TOP_N];
    size_t n = 0;

    for (size_t i = 0; i <= t->mask; i++) {
        const WordEntry *e = &t->slots[i];
        if (e->count == 0)
            continue;
        if (n == TOP_N && !ranks_before(t, e, top[n - 1]))
            continue;

        size_t j = n < TOP_N ? n++ : TOP_N - 1;
        while (j > 0 && ranks_before(t, e, top[j - 1])) {
            top[j] = top[j - 1];
            j--;
        }
        top[j] = e;
    }

    for (size_t i = 0; i < n; i++) {
        fprintf(out, "%" PRIu64 " ", top[i]->count);
        fwrite(t->arena + top[i]->off, 1, top[i]->len, out);
        fputc('\n', out);
    }
}

int cmd_wordfreq(FILE *in, FILE *out)
{
    /* Maps each byte to its lowercase letter, or 0 for separators. */
    unsigned char fold[256] = { 0 };
    for (int c = 'a'; c <= 'z'; c++) {
        fold[c] = (unsigned char)c;
        fold[c - 'a' + 'A'] = (unsigned char)c;
    }

    WordTable table;
    table_init(&table);

    unsigned char *chunk = xmalloc(READ_CHUNK);
    size_t word_cap = 256;
    char *word = xmalloc(word_cap);
    size_t word_len = 0;
    uint64_t hash = FNV64_OFFSET;

    size_t n;
    while ((n = fread(chunk, 1, READ_CHUNK, in)) > 0) {
        for (size_t i = 0; i < n; i++) {
            unsigned char c = fold[chunk[i]];
            if (c) {
                if (word_len == word_cap) {
                    word_cap *= 2;
                    word = xrealloc(word, word_cap);
                }
                word[word_len++] = (char)c;
                hash = (hash ^ c) * FNV64_PRIME;
            } else if (word_len) {
                table_add(&table, word, word_len, hash);
                word_len = 0;
                hash = FNV64_OFFSET;
            }
        }
    }
    if (word_len)
        table_add(&table, word, word_len, hash);

    print_top(&table, out);

    free(word);
    free(chunk);
    table_free(&table);
    return 0;
}
