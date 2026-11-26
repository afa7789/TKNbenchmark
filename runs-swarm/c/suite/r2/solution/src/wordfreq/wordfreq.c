/*
 * `app wordfreq`: print the 10 most frequent words of standard input.
 *
 * A word is a maximal run of ASCII letters, folded to lowercase. Input is
 * streamed in fixed-size chunks; a word straddling a chunk boundary is
 * accumulated in a growable buffer. Distinct words are counted in an
 * open-addressing hash table whose keys live in a single byte arena, and the
 * top entries are then picked with a bounded insertion selection.
 */
#include "wordfreq.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    TOP_N = 10,
    READ_CHUNK = 1 << 16,
    INITIAL_SLOTS = 1 << 12,   /* power of two */
    INITIAL_ARENA = 1 << 16,
};

/* ---- growable byte buffer --------------------------------------------- */

struct bytebuf {
    char *data;
    size_t len;
    size_t cap;
};

static bool bytebuf_reserve(struct bytebuf *b, size_t extra)
{
    if (extra <= b->cap - b->len)
        return true;
    if (extra > SIZE_MAX - b->len)
        return false;

    size_t need = b->len + extra;
    size_t cap = b->cap ? b->cap : INITIAL_ARENA;
    while (cap < need)
        cap = cap > SIZE_MAX / 2 ? need : cap * 2;

    char *p = realloc(b->data, cap);
    if (!p)
        return false;
    b->data = p;
    b->cap = cap;
    return true;
}

static bool bytebuf_append(struct bytebuf *b, const char *src, size_t n)
{
    if (!bytebuf_reserve(b, n))
        return false;
    memcpy(b->data + b->len, src, n);
    b->len += n;
    return true;
}

/* ---- word table -------------------------------------------------------- */

struct entry {
    uint64_t hash;
    size_t offset;   /* into the arena */
    size_t len;      /* 0 marks an empty slot: words are never empty */
    uint64_t count;
};

struct table {
    struct entry *slots;
    size_t mask;     /* slot count - 1 */
    size_t used;
    struct bytebuf arena;
};

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

static bool table_init(struct table *t)
{
    t->slots = calloc(INITIAL_SLOTS, sizeof *t->slots);
    if (!t->slots)
        return false;
    t->mask = INITIAL_SLOTS - 1;
    t->used = 0;
    t->arena = (struct bytebuf){ 0 };
    return true;
}

static void table_free(struct table *t)
{
    free(t->slots);
    free(t->arena.data);
}

static bool table_grow(struct table *t)
{
    size_t nslots = (t->mask + 1) * 2;
    if (nslots > SIZE_MAX / sizeof(struct entry))
        return false;

    struct entry *slots = calloc(nslots, sizeof *slots);
    if (!slots)
        return false;

    size_t mask = nslots - 1;
    for (size_t i = 0; i <= t->mask; i++) {
        const struct entry *e = &t->slots[i];
        if (e->len == 0)
            continue;
        size_t j = (size_t)e->hash & mask;
        while (slots[j].len != 0)
            j = (j + 1) & mask;
        slots[j] = *e;
    }

    free(t->slots);
    t->slots = slots;
    t->mask = mask;
    return true;
}

/* Count one occurrence of the lowercase word w[0..n), n > 0. */
static bool table_add(struct table *t, const char *w, size_t n)
{
    uint64_t h = hash_bytes(w, n);
    size_t i = (size_t)h & t->mask;

    for (;;) {
        struct entry *e = &t->slots[i];
        if (e->len == 0)
            break;
        if (e->hash == h && e->len == n &&
            memcmp(t->arena.data + e->offset, w, n) == 0) {
            e->count++;
            return true;
        }
        i = (i + 1) & t->mask;
    }

    size_t offset = t->arena.len;
    if (!bytebuf_append(&t->arena, w, n))
        return false;
    t->slots[i] = (struct entry){ .hash = h, .offset = offset, .len = n, .count = 1 };
    t->used++;

    /* Keep the load factor at or below 1/2. */
    if (t->used * 2 > t->mask + 1)
        return table_grow(t);
    return true;
}

/* ---- tokenizer --------------------------------------------------------- */

/* Maps a byte to its lowercase letter, or 0 if it is not an ASCII letter. */
static unsigned char letter_of[256];

static void init_letters(void)
{
    for (int c = 'a'; c <= 'z'; c++) {
        letter_of[c] = (unsigned char)c;
        letter_of[c - 'a' + 'A'] = (unsigned char)c;
    }
}

/*
 * Lowercase and count every word in buf[0..n). A word cut off at the end of
 * the chunk is moved to `pending`; one carried in from the previous chunk is
 * completed with the leading letters of this one.
 */
static bool scan_chunk(struct table *t, struct bytebuf *pending, char *buf, size_t n)
{
    size_t i = 0;

    while (i < n) {
        if (!letter_of[(unsigned char)buf[i]]) {
            /* A separator completes any word carried from the last chunk. */
            if (pending->len > 0) {
                if (!table_add(t, pending->data, pending->len))
                    return false;
                pending->len = 0;
            }
            i++;
            continue;
        }

        size_t start = i;
        do {
            buf[i] = (char)letter_of[(unsigned char)buf[i]];
            i++;
        } while (i < n && letter_of[(unsigned char)buf[i]]);

        if (i == n)   /* may continue in the next chunk */
            return bytebuf_append(pending, buf + start, i - start);

        if (pending->len > 0) {
            if (!bytebuf_append(pending, buf + start, i - start) ||
                !table_add(t, pending->data, pending->len))
                return false;
            pending->len = 0;
        } else if (!table_add(t, buf + start, i - start)) {
            return false;
        }
    }

    return true;
}

/* ---- ranking ----------------------------------------------------------- */

static int compare_words(const struct table *t, const struct entry *a, const struct entry *b)
{
    size_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(t->arena.data + a->offset, t->arena.data + b->offset, n);
    if (c != 0)
        return c;
    return (a->len > b->len) - (a->len < b->len);
}

/* True if a ranks strictly before b: higher count, then smaller word. */
static bool ranks_before(const struct table *t, const struct entry *a, const struct entry *b)
{
    if (a->count != b->count)
        return a->count > b->count;
    return compare_words(t, a, b) < 0;
}

/* Fill top[] with the best entries in rank order; returns how many. */
static size_t select_top(const struct table *t, const struct entry *top[TOP_N])
{
    size_t k = 0;

    for (size_t i = 0; i <= t->mask; i++) {
        const struct entry *e = &t->slots[i];
        if (e->len == 0)
            continue;
        if (k == TOP_N && !ranks_before(t, e, top[k - 1]))
            continue;

        size_t j = k < TOP_N ? k++ : TOP_N - 1;
        while (j > 0 && ranks_before(t, e, top[j - 1])) {
            top[j] = top[j - 1];
            j--;
        }
        top[j] = e;
    }
    return k;
}

/* ---- entry point ------------------------------------------------------- */

int wordfreq_main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    int status = EXIT_FAILURE;
    struct table table;
    struct bytebuf pending = { 0 };
    char *chunk = malloc(READ_CHUNK);

    if (!chunk || !table_init(&table)) {
        free(chunk);
        fputs("wordfreq: out of memory\n", stderr);
        return EXIT_FAILURE;
    }
    init_letters();

    size_t n;
    while ((n = fread(chunk, 1, READ_CHUNK, stdin)) > 0) {
        if (!scan_chunk(&table, &pending, chunk, n)) {
            fputs("wordfreq: out of memory\n", stderr);
            goto out;
        }
    }
    if (ferror(stdin)) {
        perror("wordfreq: read error");
        goto out;
    }
    if (pending.len > 0 && !table_add(&table, pending.data, pending.len)) {
        fputs("wordfreq: out of memory\n", stderr);
        goto out;
    }

    const struct entry *top[TOP_N];
    size_t k = select_top(&table, top);
    for (size_t i = 0; i < k; i++) {
        printf("%llu ", (unsigned long long)top[i]->count);
        fwrite(table.arena.data + top[i]->offset, 1, top[i]->len, stdout);
        putchar('\n');
    }
    if (fflush(stdout) != 0) {
        perror("wordfreq: write error");
        goto out;
    }
    status = EXIT_SUCCESS;

out:
    free(pending.data);
    free(chunk);
    table_free(&table);
    return status;
}
