/*
 * wordfreq: read stdin, print the 10 most frequent ASCII-letter words
 * (case-folded), ordered by count descending, then word ascending.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { TOP_N = 10, READ_CHUNK = 1 << 16, INITIAL_BUCKETS = 1 << 12 };

typedef struct {
    char *word;     /* owned, not NUL-terminated */
    size_t len;
    uint64_t hash;
    uint64_t count; /* 0 marks an empty slot */
} Entry;

typedef struct {
    Entry *slots;
    size_t cap; /* power of two */
    size_t used;
} Table;

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} Buffer;

static void die_oom(void)
{
    fputs("wordfreq: out of memory\n", stderr);
    exit(EXIT_FAILURE);
}

static void *xmalloc(size_t n)
{
    void *p = malloc(n);
    if (!p)
        die_oom();
    return p;
}

static void *xcalloc(size_t n, size_t size)
{
    void *p = calloc(n, size);
    if (!p)
        die_oom();
    return p;
}

static uint64_t hash_bytes(const char *s, size_t n)
{
    /* FNV-1a, 64-bit. */
    uint64_t h = 0xcbf29ce484222325u;
    for (size_t i = 0; i < n; i++) {
        h ^= (unsigned char)s[i];
        h *= 0x100000001b3u;
    }
    return h;
}

static void table_init(Table *t)
{
    t->cap = INITIAL_BUCKETS;
    t->used = 0;
    t->slots = xcalloc(t->cap, sizeof *t->slots);
}

static void table_free(Table *t)
{
    for (size_t i = 0; i < t->cap; i++)
        free(t->slots[i].word);
    free(t->slots);
    t->slots = NULL;
    t->cap = t->used = 0;
}

static void table_grow(Table *t)
{
    size_t new_cap = t->cap * 2;
    Entry *slots = xcalloc(new_cap, sizeof *slots);
    size_t mask = new_cap - 1;

    for (size_t i = 0; i < t->cap; i++) {
        Entry *e = &t->slots[i];
        if (e->count == 0)
            continue;
        size_t j = (size_t)e->hash & mask;
        while (slots[j].count != 0)
            j = (j + 1) & mask;
        slots[j] = *e;
    }
    free(t->slots);
    t->slots = slots;
    t->cap = new_cap;
}

static void table_add(Table *t, const char *word, size_t len)
{
    uint64_t h = hash_bytes(word, len);
    size_t mask = t->cap - 1;
    size_t i = (size_t)h & mask;

    for (;;) {
        Entry *e = &t->slots[i];
        if (e->count == 0)
            break;
        if (e->hash == h && e->len == len && memcmp(e->word, word, len) == 0) {
            e->count++;
            return;
        }
        i = (i + 1) & mask;
    }

    Entry *e = &t->slots[i];
    e->word = xmalloc(len);
    memcpy(e->word, word, len);
    e->len = len;
    e->hash = h;
    e->count = 1;

    /* Keep load factor at or below 1/2. */
    if (++t->used * 2 > t->cap)
        table_grow(t);
}

static void buffer_push(Buffer *b, char c)
{
    if (b->len == b->cap) {
        size_t new_cap = b->cap ? b->cap * 2 : 64;
        char *p = realloc(b->data, new_cap);
        if (!p)
            die_oom();
        b->data = p;
        b->cap = new_cap;
    }
    b->data[b->len++] = c;
}

/* True if a should be ranked before b. */
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

static size_t select_top(const Table *t, const Entry *top[TOP_N])
{
    size_t n = 0;
    for (size_t i = 0; i < t->cap; i++) {
        const Entry *e = &t->slots[i];
        if (e->count == 0)
            continue;
        if (n == TOP_N && !ranks_before(e, top[n - 1]))
            continue;
        size_t j = n < TOP_N ? n++ : TOP_N - 1;
        while (j > 0 && ranks_before(e, top[j - 1])) {
            top[j] = top[j - 1];
            j--;
        }
        top[j] = e;
    }
    return n;
}

static inline bool is_alpha(unsigned char c)
{
    return (unsigned char)((c | 0x20) - 'a') < 26;
}

int main(void)
{
    static char chunk[READ_CHUNK];
    Table table;
    Buffer word = {0};
    size_t nread;

    table_init(&table);

    while ((nread = fread(chunk, 1, sizeof chunk, stdin)) > 0) {
        size_t i = 0;
        while (i < nread) {
            if (!is_alpha((unsigned char)chunk[i])) {
                if (word.len > 0) {
                    table_add(&table, word.data, word.len);
                    word.len = 0;
                }
                i++;
                continue;
            }
            /* Fast path: word lies entirely within this chunk. */
            size_t start = i;
            while (i < nread && is_alpha((unsigned char)chunk[i])) {
                chunk[i] |= 0x20;
                i++;
            }
            if (word.len == 0 && i < nread) {
                table_add(&table, chunk + start, i - start);
            } else {
                for (size_t k = start; k < i; k++)
                    buffer_push(&word, chunk[k]);
                if (i < nread) {
                    table_add(&table, word.data, word.len);
                    word.len = 0;
                }
            }
        }
    }
    if (word.len > 0)
        table_add(&table, word.data, word.len);

    const Entry *top[TOP_N];
    size_t n = select_top(&table, top);
    for (size_t i = 0; i < n; i++) {
        printf("%llu ", (unsigned long long)top[i]->count);
        fwrite(top[i]->word, 1, top[i]->len, stdout);
        putchar('\n');
    }

    free(word.data);
    table_free(&table);
    fflush(stdout);
    return EXIT_SUCCESS;
}
