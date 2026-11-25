/* wordfreq: print the 10 most frequent ASCII-letter words read from stdin. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { TOP_N = 10 };

/* A distinct word: its bytes live (already lowercased) inside the input buffer. */
typedef struct {
    const unsigned char *word;
    size_t len;
    size_t count;
    uint64_t hash;
} Entry;

typedef struct {
    Entry *slots; /* word == NULL marks an empty slot */
    size_t cap;   /* power of two */
    size_t len;
} Table;

/* Read all of stream into a heap buffer. Returns NULL on error. */
static unsigned char *read_all(FILE *in, size_t *out_len)
{
    size_t cap = 1 << 16, len = 0;
    unsigned char *buf = malloc(cap);
    if (!buf)
        return NULL;
    for (;;) {
        if (len == cap) {
            if (cap > SIZE_MAX / 2) {
                free(buf);
                return NULL;
            }
            size_t ncap = cap * 2;
            unsigned char *p = realloc(buf, ncap);
            if (!p) {
                free(buf);
                return NULL;
            }
            buf = p;
            cap = ncap;
        }
        size_t n = fread(buf + len, 1, cap - len, in);
        len += n;
        if (n == 0) {
            if (ferror(in)) {
                free(buf);
                return NULL;
            }
            break;
        }
    }
    *out_len = len;
    return buf;
}

static inline bool is_alpha(unsigned char c)
{
    return (unsigned char)((c | 0x20) - 'a') < 26;
}

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

static bool table_init(Table *t, size_t cap)
{
    t->slots = calloc(cap, sizeof *t->slots);
    t->cap = cap;
    t->len = 0;
    return t->slots != NULL;
}

static bool table_grow(Table *t)
{
    if (t->cap > SIZE_MAX / 2 / sizeof *t->slots)
        return false;
    size_t ncap = t->cap * 2;
    Entry *ns = calloc(ncap, sizeof *ns);
    if (!ns)
        return false;
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
    return true;
}

/* Count one occurrence of word[0..len). Returns false on allocation failure. */
static bool table_add(Table *t, const unsigned char *word, size_t len)
{
    if ((t->len + 1) * 4 > t->cap * 3 && !table_grow(t))
        return false;
    uint64_t h = hash_bytes(word, len);
    size_t mask = t->cap - 1;
    size_t i = (size_t)h & mask;
    for (;;) {
        Entry *e = &t->slots[i];
        if (!e->word) {
            *e = (Entry){ .word = word, .len = len, .count = 1, .hash = h };
            t->len++;
            return true;
        }
        if (e->hash == h && e->len == len && memcmp(e->word, word, len) == 0) {
            e->count++;
            return true;
        }
        i = (i + 1) & mask;
    }
}

/* Byte-order comparison of two words; shorter prefix sorts first. */
static int word_cmp(const Entry *a, const Entry *b)
{
    size_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->word, b->word, n);
    if (c != 0)
        return c;
    return (a->len > b->len) - (a->len < b->len);
}

/* True if a should be listed before b. */
static bool ranks_before(const Entry *a, const Entry *b)
{
    if (a->count != b->count)
        return a->count > b->count;
    return word_cmp(a, b) < 0;
}

int main(void)
{
    size_t n = 0;
    unsigned char *buf = read_all(stdin, &n);
    if (!buf) {
        fputs("wordfreq: failed to read input\n", stderr);
        return EXIT_FAILURE;
    }

    Table t;
    if (!table_init(&t, 1024)) {
        fputs("wordfreq: out of memory\n", stderr);
        free(buf);
        return EXIT_FAILURE;
    }

    size_t i = 0;
    while (i < n) {
        if (!is_alpha(buf[i])) {
            i++;
            continue;
        }
        size_t start = i;
        do {
            buf[i] |= 0x20; /* ASCII letter to lowercase */
            i++;
        } while (i < n && is_alpha(buf[i]));
        if (!table_add(&t, buf + start, i - start)) {
            fputs("wordfreq: out of memory\n", stderr);
            free(t.slots);
            free(buf);
            return EXIT_FAILURE;
        }
    }

    /* Keep the best TOP_N entries in rank order via insertion. */
    const Entry *top[TOP_N];
    size_t ntop = 0;
    for (size_t s = 0; s < t.cap; s++) {
        const Entry *e = &t.slots[s];
        if (!e->word)
            continue;
        if (ntop == TOP_N && !ranks_before(e, top[TOP_N - 1]))
            continue;
        size_t k = ntop < TOP_N ? ntop++ : TOP_N - 1;
        while (k > 0 && ranks_before(e, top[k - 1])) {
            top[k] = top[k - 1];
            k--;
        }
        top[k] = e;
    }

    for (size_t k = 0; k < ntop; k++) {
        printf("%zu ", top[k]->count);
        fwrite(top[k]->word, 1, top[k]->len, stdout);
        putchar('\n');
    }

    int status = EXIT_SUCCESS;
    if (fflush(stdout) != 0 || ferror(stdout)) {
        fputs("wordfreq: write error\n", stderr);
        status = EXIT_FAILURE;
    }
    free(t.slots);
    free(buf);
    return status;
}
