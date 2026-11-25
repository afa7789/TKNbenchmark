/*
 * wordfreq: read standard input and print the 10 most frequent words.
 *
 * A word is a maximal run of ASCII letters, folded to lowercase. Output is
 * "<count> <word>" per line, by count descending, then word ascending.
 */
#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { TOP_N = 10 };

/* ---------- input ---------- */

typedef struct {
    unsigned char *data;
    size_t len;
} Buffer;

/* Read all of `in` into a heap buffer. Returns 0 or an errno value. */
static int read_all(FILE *in, Buffer *out)
{
    size_t cap = 1u << 20, len = 0;
    unsigned char *data = malloc(cap);
    if (!data)
        return ENOMEM;

    for (;;) {
        if (len == cap) {
            if (cap > SIZE_MAX / 2) {
                free(data);
                return ENOMEM;
            }
            size_t ncap = cap * 2;
            unsigned char *p = realloc(data, ncap);
            if (!p) {
                free(data);
                return ENOMEM;
            }
            data = p;
            cap = ncap;
        }
        size_t n = fread(data + len, 1, cap - len, in);
        len += n;
        if (n == 0) {
            if (ferror(in)) {
                free(data);
                return EIO;
            }
            break;
        }
    }
    out->data = data;
    out->len = len;
    return 0;
}

/* ---------- hash table of words (keys point into the input buffer) ---------- */

typedef struct {
    const unsigned char *word; /* NULL marks an empty slot */
    size_t len;
    uint64_t hash;
    size_t count;
} Entry;

typedef struct {
    Entry *slots;
    size_t cap; /* power of two */
    size_t used;
} Table;

static uint64_t hash_bytes(const unsigned char *s, size_t n)
{
    uint64_t h = 0xcbf29ce484222325u; /* FNV-1a */
    for (size_t i = 0; i < n; i++) {
        h ^= s[i];
        h *= 0x100000001b3u;
    }
    return h ^ (h >> 29);
}

static int table_init(Table *t, size_t cap)
{
    t->slots = calloc(cap, sizeof *t->slots);
    if (!t->slots)
        return ENOMEM;
    t->cap = cap;
    t->used = 0;
    return 0;
}

static int table_grow(Table *t)
{
    if (t->cap > SIZE_MAX / 2 / sizeof *t->slots)
        return ENOMEM;
    size_t ncap = t->cap * 2;
    Entry *ns = calloc(ncap, sizeof *ns);
    if (!ns)
        return ENOMEM;

    size_t mask = ncap - 1;
    for (size_t i = 0; i < t->cap; i++) {
        const Entry *e = &t->slots[i];
        if (!e->word)
            continue;
        size_t j = (size_t)e->hash & mask;
        while (ns[j].word)
            j = (j + 1) & mask;
        ns[j] = *e;
    }
    free(t->slots);
    t->slots = ns;
    t->cap = ncap;
    return 0;
}

/* Count one occurrence of word[0..len). Returns 0 or an errno value. */
static int table_add(Table *t, const unsigned char *word, size_t len)
{
    uint64_t h = hash_bytes(word, len);
    size_t mask = t->cap - 1;
    size_t i = (size_t)h & mask;

    for (;;) {
        Entry *e = &t->slots[i];
        if (!e->word)
            break;
        if (e->hash == h && e->len == len && memcmp(e->word, word, len) == 0) {
            e->count++;
            return 0;
        }
        i = (i + 1) & mask;
    }

    t->slots[i] = (Entry){ .word = word, .len = len, .hash = h, .count = 1 };
    t->used++;
    if (t->used * 2 > t->cap)
        return table_grow(t);
    return 0;
}

/* ---------- ranking ---------- */

/* True if a ranks strictly before b: higher count, then smaller word. */
static bool ranks_before(const Entry *a, const Entry *b)
{
    if (a->count != b->count)
        return a->count > b->count;
    size_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->word, b->word, n);
    if (c != 0)
        return c < 0;
    return a->len < b->len;
}

/* Collect the best `TOP_N` entries into top[], sorted; returns how many. */
static size_t select_top(const Table *t, const Entry *top[TOP_N])
{
    size_t n = 0;
    for (size_t i = 0; i < t->cap; i++) {
        const Entry *e = &t->slots[i];
        if (!e->word)
            continue;
        if (n == TOP_N && !ranks_before(e, top[n - 1]))
            continue;

        size_t pos = n < TOP_N ? n++ : TOP_N - 1;
        while (pos > 0 && ranks_before(e, top[pos - 1])) {
            top[pos] = top[pos - 1];
            pos--;
        }
        top[pos] = e;
    }
    return n;
}

/* ---------- main ---------- */

static inline bool is_alpha(unsigned char c)
{
    return (unsigned char)((c | 0x20u) - 'a') < 26u;
}

int main(void)
{
    Buffer in = { 0 };
    Table table = { 0 };
    int err = read_all(stdin, &in);
    if (err)
        goto out;
    if ((err = table_init(&table, 1u << 12)) != 0)
        goto out;

    for (size_t i = 0; i < in.len;) {
        if (!is_alpha(in.data[i])) {
            i++;
            continue;
        }
        size_t start = i;
        for (; i < in.len && is_alpha(in.data[i]); i++)
            in.data[i] |= 0x20u; /* ASCII letters: set bit 5 to lowercase */
        if ((err = table_add(&table, in.data + start, i - start)) != 0)
            goto out;
    }

    const Entry *top[TOP_N];
    size_t n = select_top(&table, top);
    for (size_t k = 0; k < n; k++)
        printf("%zu %.*s\n", top[k]->count, (int)top[k]->len, (const char *)top[k]->word);

    if (fflush(stdout) != 0)
        err = errno ? errno : EIO;

out:
    if (err)
        fprintf(stderr, "wordfreq: %s\n", strerror(err));
    free(table.slots);
    free(in.data);
    return err ? EXIT_FAILURE : EXIT_SUCCESS;
}
