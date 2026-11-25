/*
 * wordfreq: read standard input and print the 10 most frequent words.
 *
 * A word is a maximal run of ASCII letters, folded to lowercase. Output is
 * "<count> <word>" per line, by count descending, then word ascending.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TOP_N 10

typedef struct {
    const unsigned char *word; /* points into the input buffer; NULL = empty slot */
    size_t len;
    size_t count;
    uint64_t hash;
} Entry;

typedef struct {
    Entry *slots;
    size_t cap; /* power of two */
    size_t len;
} Table;

typedef struct {
    unsigned char *data;
    size_t len;
} Buffer;

static void die(const char *msg)
{
    fprintf(stderr, "wordfreq: %s\n", msg);
    exit(EXIT_FAILURE);
}

/* Read the whole stream into memory. */
static Buffer read_all(FILE *in)
{
    Buffer b = {0};
    size_t cap = 1u << 20;
    b.data = malloc(cap);
    if (!b.data)
        die("out of memory");

    for (;;) {
        if (b.len == cap) {
            if (cap > SIZE_MAX / 2)
                die("input too large");
            size_t ncap = cap * 2;
            unsigned char *p = realloc(b.data, ncap);
            if (!p)
                die("out of memory");
            b.data = p;
            cap = ncap;
        }
        size_t n = fread(b.data + b.len, 1, cap - b.len, in);
        b.len += n;
        if (n == 0) {
            if (ferror(in))
                die("read error");
            break;
        }
    }
    return b;
}

static inline bool is_upper(unsigned char c) { return c >= 'A' && c <= 'Z'; }
static inline bool is_lower(unsigned char c) { return c >= 'a' && c <= 'z'; }

/* FNV-1a, 64-bit. */
static inline uint64_t hash_bytes(const unsigned char *s, size_t n)
{
    uint64_t h = 0xcbf29ce484222325u;
    for (size_t i = 0; i < n; i++) {
        h ^= s[i];
        h *= 0x100000001b3u;
    }
    return h;
}

static void table_init(Table *t, size_t cap)
{
    t->slots = calloc(cap, sizeof *t->slots);
    if (!t->slots)
        die("out of memory");
    t->cap = cap;
    t->len = 0;
}

static void table_grow(Table *t)
{
    if (t->cap > SIZE_MAX / 2 / sizeof *t->slots)
        die("too many words");
    size_t ncap = t->cap * 2;
    Entry *ns = calloc(ncap, sizeof *ns);
    if (!ns)
        die("out of memory");
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
}

static void table_add(Table *t, const unsigned char *word, size_t len)
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
            return;
        }
        i = (i + 1) & mask;
    }
    t->slots[i] = (Entry){.word = word, .len = len, .count = 1, .hash = h};
    t->len++;
    /* Keep the load factor at or below 3/4. */
    if (t->len * 4 > t->cap * 3)
        table_grow(t);
}

/* Byte-wise comparison of two words; a proper prefix sorts first. */
static int word_cmp(const Entry *a, const Entry *b)
{
    size_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->word, b->word, n);
    if (c != 0)
        return c;
    return (a->len > b->len) - (a->len < b->len);
}

/* True if a ranks ahead of b in the output order. */
static bool ranks_before(const Entry *a, const Entry *b)
{
    if (a->count != b->count)
        return a->count > b->count;
    return word_cmp(a, b) < 0;
}

/* Select the top entries into out (sorted); returns how many were found. */
static size_t top_entries(const Table *t, const Entry **out, size_t k)
{
    size_t n = 0;
    for (size_t i = 0; i < t->cap; i++) {
        const Entry *e = &t->slots[i];
        if (!e->word)
            continue;
        if (n == k && !ranks_before(e, out[n - 1]))
            continue;
        size_t j = n < k ? n++ : k - 1;
        while (j > 0 && ranks_before(e, out[j - 1])) {
            out[j] = out[j - 1];
            j--;
        }
        out[j] = e;
    }
    return n;
}

int main(void)
{
    Buffer in = read_all(stdin);

    Table t;
    table_init(&t, 1u << 12);

    unsigned char *p = in.data;
    unsigned char *end = in.data + in.len;
    while (p < end) {
        while (p < end && !is_upper(*p) && !is_lower(*p))
            p++;
        unsigned char *start = p;
        for (; p < end; p++) {
            if (is_upper(*p))
                *p = (unsigned char)(*p - 'A' + 'a');
            else if (!is_lower(*p))
                break;
        }
        if (p > start)
            table_add(&t, start, (size_t)(p - start));
    }

    const Entry *top[TOP_N];
    size_t n = top_entries(&t, top, TOP_N);
    for (size_t i = 0; i < n; i++) {
        printf("%zu ", top[i]->count);
        fwrite(top[i]->word, 1, top[i]->len, stdout);
        putchar('\n');
    }

    if (fflush(stdout) != 0)
        die("write error");

    free(t.slots);
    free(in.data);
    return EXIT_SUCCESS;
}
