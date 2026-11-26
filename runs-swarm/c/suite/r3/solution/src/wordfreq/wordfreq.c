/* wordfreq: word frequencies. See the "wordfreq" section of SPEC.md.
 *
 * Standard input is streamed in fixed-size chunks. Each word (a maximal run
 * of ASCII letters) is folded to lowercase into a scratch buffer, which lets
 * words span chunk boundaries, and is then counted in an open-addressing hash
 * table. Distinct word texts live in a single growable arena that the table
 * references by offset. Finally one pass over the table keeps the best
 * WF_TOP entries in a small sorted array.
 */

#include "wordfreq/wordfreq.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    WF_TOP = 10,                  /* number of words printed */
    WF_CHUNK = 64 * 1024,         /* bytes read from stdin at a time */
    WF_INITIAL_SLOTS = 1024,      /* hash table size; must be a power of two */
};

/* A growable byte buffer. */
struct wf_buf {
    char *data;
    size_t len;
    size_t cap;
};

/* One hash table slot; count == 0 marks an empty slot. */
struct wf_entry {
    uint64_t hash;
    size_t off;                   /* offset of the word in the arena */
    size_t len;
    uint64_t count;
};

struct wf_table {
    struct wf_entry *slots;
    size_t cap;                   /* power of two */
    size_t used;
    struct wf_buf arena;          /* concatenated text of all distinct words */
};

/* Maps letters to lowercase and every other byte to 0 (a separator). */
static unsigned char wf_fold[256];

static void wf_init_fold(void)
{
    for (int c = 'a'; c <= 'z'; c++) {
        wf_fold[c] = (unsigned char)c;
        wf_fold[c - 'a' + 'A'] = (unsigned char)c;
    }
}

static bool wf_buf_reserve(struct wf_buf *b, size_t extra)
{
    if (b->cap - b->len >= extra)
        return true;
    if (extra > SIZE_MAX - b->len)
        return false;

    size_t need = b->len + extra;
    size_t cap = b->cap ? b->cap : 64;
    while (cap < need)
        cap = cap > SIZE_MAX / 2 ? need : cap * 2;

    char *data = realloc(b->data, cap);
    if (!data)
        return false;
    b->data = data;
    b->cap = cap;
    return true;
}

static bool wf_buf_push(struct wf_buf *b, char c)
{
    if (b->len == b->cap && !wf_buf_reserve(b, 1))
        return false;
    b->data[b->len++] = c;
    return true;
}

/* 64-bit FNV-1a. */
static uint64_t wf_hash(const char *s, size_t len)
{
    uint64_t h = 0xcbf29ce484222325u;
    for (size_t i = 0; i < len; i++) {
        h ^= (unsigned char)s[i];
        h *= 0x100000001b3u;
    }
    return h;
}

static bool wf_table_init(struct wf_table *t)
{
    *t = (struct wf_table){ 0 };
    t->slots = calloc(WF_INITIAL_SLOTS, sizeof *t->slots);
    if (!t->slots)
        return false;
    t->cap = WF_INITIAL_SLOTS;
    return true;
}

static void wf_table_free(struct wf_table *t)
{
    free(t->slots);
    free(t->arena.data);
    *t = (struct wf_table){ 0 };
}

/* Doubles the slot array and reinserts every entry. */
static bool wf_table_grow(struct wf_table *t)
{
    if (t->cap > SIZE_MAX / 2 / sizeof *t->slots)
        return false;

    size_t cap = t->cap * 2;
    struct wf_entry *slots = calloc(cap, sizeof *slots);
    if (!slots)
        return false;

    size_t mask = cap - 1;
    for (size_t i = 0; i < t->cap; i++) {
        const struct wf_entry *e = &t->slots[i];
        if (e->count == 0)
            continue;
        size_t j = (size_t)e->hash & mask;
        while (slots[j].count != 0)
            j = (j + 1) & mask;
        slots[j] = *e;
    }

    free(t->slots);
    t->slots = slots;
    t->cap = cap;
    return true;
}

/* Counts one occurrence of the word w[0..len). */
static bool wf_table_add(struct wf_table *t, const char *w, size_t len)
{
    uint64_t hash = wf_hash(w, len);
    size_t mask = t->cap - 1;
    size_t i = (size_t)hash & mask;

    for (;;) {
        struct wf_entry *e = &t->slots[i];
        if (e->count == 0)
            break;
        if (e->hash == hash && e->len == len &&
            memcmp(t->arena.data + e->off, w, len) == 0) {
            e->count++;
            return true;
        }
        i = (i + 1) & mask;
    }

    /* New word: keep the load factor at or below 1/2. */
    if ((t->used + 1) * 2 > t->cap) {
        if (!wf_table_grow(t))
            return false;
        mask = t->cap - 1;
        i = (size_t)hash & mask;
        while (t->slots[i].count != 0)
            i = (i + 1) & mask;
    }

    if (!wf_buf_reserve(&t->arena, len))
        return false;
    memcpy(t->arena.data + t->arena.len, w, len);
    t->slots[i] = (struct wf_entry){
        .hash = hash, .off = t->arena.len, .len = len, .count = 1,
    };
    t->arena.len += len;
    t->used++;
    return true;
}

/* Reads all of `in`, counting its words into `t`. */
static bool wf_count_words(FILE *in, struct wf_table *t)
{
    static char chunk[WF_CHUNK];
    struct wf_buf word = { 0 };
    bool ok = true;
    size_t n;

    while (ok && (n = fread(chunk, 1, sizeof chunk, in)) > 0) {
        for (size_t i = 0; i < n; i++) {
            unsigned char c = wf_fold[(unsigned char)chunk[i]];
            if (c) {
                if (!wf_buf_push(&word, (char)c)) {
                    ok = false;
                    break;
                }
            } else if (word.len > 0) {
                if (!wf_table_add(t, word.data, word.len)) {
                    ok = false;
                    break;
                }
                word.len = 0;
            }
        }
    }
    if (ok && word.len > 0)
        ok = wf_table_add(t, word.data, word.len);

    free(word.data);
    return ok;
}

/* True if entry a ranks before entry b: higher count, then smaller word. */
static bool wf_ranks_before(const struct wf_table *t,
                            const struct wf_entry *a, const struct wf_entry *b)
{
    if (a->count != b->count)
        return a->count > b->count;

    size_t n = a->len < b->len ? a->len : b->len;
    int cmp = memcmp(t->arena.data + a->off, t->arena.data + b->off, n);
    if (cmp != 0)
        return cmp < 0;
    return a->len < b->len;
}

/* Fills top[] with the best entries in rank order; returns how many. */
static size_t wf_select_top(const struct wf_table *t,
                            const struct wf_entry *top[WF_TOP])
{
    size_t n = 0;

    for (size_t i = 0; i < t->cap; i++) {
        const struct wf_entry *e = &t->slots[i];
        if (e->count == 0)
            continue;
        if (n == WF_TOP && !wf_ranks_before(t, e, top[n - 1]))
            continue;

        size_t j = n < WF_TOP ? n++ : n - 1;
        while (j > 0 && wf_ranks_before(t, e, top[j - 1])) {
            top[j] = top[j - 1];
            j--;
        }
        top[j] = e;
    }
    return n;
}

int wordfreq_main(int argc, char **argv)
{
    (void)argc;
    const char *prog = argv[0];

    wf_init_fold();

    struct wf_table table;
    if (!wf_table_init(&table)) {
        fprintf(stderr, "%s: out of memory\n", prog);
        return 1;
    }

    if (!wf_count_words(stdin, &table)) {
        fprintf(stderr, "%s: out of memory\n", prog);
        wf_table_free(&table);
        return 1;
    }
    if (ferror(stdin)) {
        perror(prog);
        wf_table_free(&table);
        return 1;
    }

    const struct wf_entry *top[WF_TOP];
    size_t n = wf_select_top(&table, top);
    for (size_t i = 0; i < n; i++) {
        printf("%llu ", (unsigned long long)top[i]->count);
        fwrite(table.arena.data + top[i]->off, 1, top[i]->len, stdout);
        putchar('\n');
    }

    wf_table_free(&table);

    if (fflush(stdout) != 0 || ferror(stdout)) {
        perror(prog);
        return 1;
    }
    return 0;
}
