/*
 * `app wordfreq`: print the 10 most frequent words of standard input.
 *
 * A word is a maximal run of ASCII letters, folded to lowercase; every other
 * byte separates words. Input is streamed in fixed-size chunks, so memory use
 * is proportional to the distinct words rather than the input size. Words are
 * counted in an open-addressing hash table whose keys live in a single
 * growable byte pool; the top entries are then selected in one pass.
 */
#include "wordfreq.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    TOP_N         = 10,
    READ_CHUNK    = 1 << 16,
    INITIAL_SLOTS = 1 << 12, /* must be a power of two */
};

/* FNV-1a, 64-bit. */
#define FNV_OFFSET UINT64_C(0xcbf29ce484222325)
#define FNV_PRIME  UINT64_C(0x100000001b3)

/* A growable byte buffer. */
struct buf {
    char  *data;
    size_t len;
    size_t cap;
};

/*
 * One distinct word; count == 0 marks an empty slot. Fields are 32-bit to
 * keep the slot array compact: a 50 MB input holds far fewer than 2^32
 * words, and table_add() refuses to go past those limits.
 */
struct entry {
    uint32_t hash;  /* low 32 bits of the word's hash */
    uint32_t count;
    uint32_t off;   /* offset of the word in the pool */
    uint32_t len;
};

struct table {
    struct entry *slots;
    size_t        mask; /* number of slots - 1 */
    size_t        used;
    struct buf    pool; /* concatenated word bytes, not NUL-terminated */
};

/* Maps each byte to its lowercase letter, or 0 if it is not a letter. */
static unsigned char fold[256];

static void init_fold(void)
{
    for (int c = 'a'; c <= 'z'; c++) {
        fold[c] = (unsigned char)c;
        fold[c - 'a' + 'A'] = (unsigned char)c;
    }
}

static bool buf_reserve(struct buf *b, size_t extra)
{
    if (b->cap - b->len >= extra)
        return true;
    if (extra > SIZE_MAX - b->len)
        return false;
    size_t need = b->len + extra;
    size_t cap = b->cap ? b->cap : 64;
    while (cap < need)
        cap = cap > SIZE_MAX / 2 ? need : cap * 2;
    char *p = realloc(b->data, cap);
    if (p == NULL)
        return false;
    b->data = p;
    b->cap = cap;
    return true;
}

static bool buf_append(struct buf *b, const char *src, size_t n)
{
    if (!buf_reserve(b, n))
        return false;
    memcpy(b->data + b->len, src, n);
    b->len += n;
    return true;
}

static bool table_init(struct table *t)
{
    t->slots = calloc(INITIAL_SLOTS, sizeof *t->slots);
    if (t->slots == NULL)
        return false;
    t->mask = INITIAL_SLOTS - 1;
    t->used = 0;
    t->pool = (struct buf){ 0 };
    return true;
}

static void table_free(struct table *t)
{
    free(t->slots);
    free(t->pool.data);
}

/* Doubles the slot array and reinserts every entry. */
static bool table_grow(struct table *t)
{
    size_t nslots = (t->mask + 1) * 2;
    struct entry *slots = calloc(nslots, sizeof *slots);
    if (slots == NULL)
        return false;
    size_t mask = nslots - 1;
    for (size_t i = 0; i <= t->mask; i++) {
        const struct entry *e = &t->slots[i];
        if (e->count == 0)
            continue;
        size_t j = e->hash & mask;
        while (slots[j].count != 0)
            j = (j + 1) & mask;
        slots[j] = *e;
    }
    free(t->slots);
    t->slots = slots;
    t->mask = mask;
    return true;
}

/* Counts one occurrence of the lowercase word w[0..len). */
static bool table_add(struct table *t, const char *w, size_t len, uint64_t hash64)
{
    uint32_t hash = (uint32_t)(hash64 ^ (hash64 >> 32));
    size_t i = hash & t->mask;
    for (;;) {
        struct entry *e = &t->slots[i];
        if (e->count == 0)
            break;
        if (e->hash == hash && e->len == len &&
            memcmp(t->pool.data + e->off, w, len) == 0) {
            if (e->count == UINT32_MAX)
                return false;
            e->count++;
            return true;
        }
        i = (i + 1) & t->mask;
    }

    size_t off = t->pool.len;
    if (len > UINT32_MAX - off || !buf_append(&t->pool, w, len))
        return false;
    t->slots[i] = (struct entry){
        .hash = hash, .count = 1, .off = (uint32_t)off, .len = (uint32_t)len,
    };
    t->used++;

    /* Keep the load factor at or below 3/4. */
    if (t->used > (t->mask + 1) / 4 * 3)
        return table_grow(t);
    return true;
}

/* Reads standard input to the end, counting every word into t. */
static bool count_words(FILE *in, struct table *t)
{
    static char chunk[READ_CHUNK];
    struct buf word = { 0 }; /* current word, possibly spanning chunks */
    uint64_t hash = FNV_OFFSET;
    bool ok = true;
    size_t n;

    while (ok && (n = fread(chunk, 1, sizeof chunk, in)) > 0) {
        for (size_t i = 0; i < n; i++) {
            unsigned char c = fold[(unsigned char)chunk[i]];
            if (c != 0) {
                if (word.len == word.cap && !buf_reserve(&word, 1)) {
                    ok = false;
                    break;
                }
                word.data[word.len++] = (char)c;
                hash = (hash ^ c) * FNV_PRIME;
            } else if (word.len > 0) {
                if (!table_add(t, word.data, word.len, hash)) {
                    ok = false;
                    break;
                }
                word.len = 0;
                hash = FNV_OFFSET;
            }
        }
    }
    if (ok && word.len > 0)
        ok = table_add(t, word.data, word.len, hash);
    free(word.data);

    if (!ok) {
        fputs("wordfreq: out of memory or input too large\n", stderr);
        return false;
    }
    if (ferror(in)) {
        perror("wordfreq: read error");
        return false;
    }
    return true;
}

/* Byte-wise comparison of two words; a proper prefix sorts first. */
static int word_cmp(const struct table *t, const struct entry *a, const struct entry *b)
{
    size_t n = a->len < b->len ? a->len : b->len;
    int r = memcmp(t->pool.data + a->off, t->pool.data + b->off, n);
    if (r != 0)
        return r;
    return (a->len > b->len) - (a->len < b->len);
}

/* True if a ranks before b: higher count first, then word ascending. */
static bool ranks_before(const struct table *t, const struct entry *a, const struct entry *b)
{
    if (a->count != b->count)
        return a->count > b->count;
    return word_cmp(t, a, b) < 0;
}

/*
 * Fills top[] with the best-ranked entries in rank order and returns how
 * many there are (at most TOP_N).
 */
static size_t select_top(const struct table *t, const struct entry *top[TOP_N])
{
    size_t k = 0;
    for (size_t i = 0; i <= t->mask; i++) {
        const struct entry *e = &t->slots[i];
        if (e->count == 0)
            continue;
        if (k == TOP_N && !ranks_before(t, e, top[k - 1]))
            continue;
        size_t j = k < TOP_N ? k++ : k - 1;
        while (j > 0 && ranks_before(t, e, top[j - 1])) {
            top[j] = top[j - 1];
            j--;
        }
        top[j] = e;
    }
    return k;
}

int wordfreq_main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    init_fold();

    struct table t;
    if (!table_init(&t)) {
        fputs("wordfreq: out of memory\n", stderr);
        return EXIT_FAILURE;
    }
    if (!count_words(stdin, &t)) {
        table_free(&t);
        return EXIT_FAILURE;
    }

    const struct entry *top[TOP_N];
    size_t k = select_top(&t, top);
    for (size_t i = 0; i < k; i++) {
        const struct entry *e = top[i];
        printf("%" PRIu32 " ", e->count);
        fwrite(t.pool.data + e->off, 1, e->len, stdout);
        putchar('\n');
    }
    table_free(&t);

    if (fflush(stdout) != 0 || ferror(stdout)) {
        perror("wordfreq: write error");
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
