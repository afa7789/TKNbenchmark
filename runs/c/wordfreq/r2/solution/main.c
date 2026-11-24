/*
 * wordfreq: read stdin, print the 10 most frequent ASCII words.
 *
 * A word is a maximal run of ASCII letters, folded to lowercase. Output is
 * "<count> <word>" per line, ordered by count descending, then word ascending
 * (byte order), at most TOP_N lines.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TOP_N 10
#define READ_CHUNK (1u << 16)
#define INITIAL_CAPACITY 1024u /* must be a power of two */

typedef struct {
    char *word;     /* NULL marks an empty slot; not NUL-terminated */
    size_t len;
    uint64_t hash;
    size_t count;
} Entry;

typedef struct {
    Entry *slots;
    size_t capacity; /* power of two */
    size_t size;
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
    if (p == NULL)
        die_oom();
    return p;
}

static void *xcalloc(size_t n, size_t size)
{
    void *p = calloc(n, size);
    if (p == NULL)
        die_oom();
    return p;
}

/* FNV-1a, 64-bit. */
static uint64_t hash_bytes(const char *s, size_t len)
{
    uint64_t h = 0xcbf29ce484222325u;
    for (size_t i = 0; i < len; i++) {
        h ^= (unsigned char)s[i];
        h *= 0x100000001b3u;
    }
    return h;
}

static void table_init(Table *t)
{
    t->capacity = INITIAL_CAPACITY;
    t->size = 0;
    t->slots = xcalloc(t->capacity, sizeof *t->slots);
}

static void table_free(Table *t)
{
    for (size_t i = 0; i < t->capacity; i++)
        free(t->slots[i].word);
    free(t->slots);
    t->slots = NULL;
    t->capacity = t->size = 0;
}

static void table_grow(Table *t)
{
    size_t new_cap = t->capacity * 2;
    Entry *new_slots = xcalloc(new_cap, sizeof *new_slots);
    size_t mask = new_cap - 1;

    for (size_t i = 0; i < t->capacity; i++) {
        Entry *e = &t->slots[i];
        if (e->word == NULL)
            continue;
        size_t j = (size_t)e->hash & mask;
        while (new_slots[j].word != NULL)
            j = (j + 1) & mask;
        new_slots[j] = *e;
    }
    free(t->slots);
    t->slots = new_slots;
    t->capacity = new_cap;
}

/* Increment the count for word[0..len), inserting it if absent. */
static void table_add(Table *t, const char *word, size_t len)
{
    uint64_t h = hash_bytes(word, len);
    size_t mask = t->capacity - 1;
    size_t i = (size_t)h & mask;

    for (;;) {
        Entry *e = &t->slots[i];
        if (e->word == NULL)
            break;
        if (e->hash == h && e->len == len && memcmp(e->word, word, len) == 0) {
            e->count++;
            return;
        }
        i = (i + 1) & mask;
    }

    /* Keep load factor <= 1/2. */
    if ((t->size + 1) * 2 > t->capacity) {
        table_grow(t);
        mask = t->capacity - 1;
        i = (size_t)h & mask;
        while (t->slots[i].word != NULL)
            i = (i + 1) & mask;
    }

    Entry *e = &t->slots[i];
    e->word = xmalloc(len);
    memcpy(e->word, word, len);
    e->len = len;
    e->hash = h;
    e->count = 1;
    t->size++;
}

static void buffer_push(Buffer *b, char c)
{
    if (b->len == b->cap) {
        size_t new_cap = b->cap ? b->cap * 2 : 64;
        char *p = realloc(b->data, new_cap);
        if (p == NULL)
            die_oom();
        b->data = p;
        b->cap = new_cap;
    }
    b->data[b->len++] = c;
}

/* Returns true if a ranks before b: higher count, then lexicographically smaller word. */
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

/* Select the top entries into out (sorted best-first); returns how many. */
static size_t select_top(const Table *t, const Entry **out, size_t max)
{
    size_t n = 0;
    for (size_t i = 0; i < t->capacity; i++) {
        const Entry *e = &t->slots[i];
        if (e->word == NULL)
            continue;
        if (n == max && !ranks_before(e, out[n - 1]))
            continue;
        size_t pos = n < max ? n++ : max - 1;
        while (pos > 0 && ranks_before(e, out[pos - 1])) {
            out[pos] = out[pos - 1];
            pos--;
        }
        out[pos] = e;
    }
    return n;
}

static inline bool is_alpha(unsigned char c)
{
    return (unsigned char)((c | 0x20) - 'a') < 26;
}

int main(void)
{
    Table table;
    Buffer word = {0};
    static unsigned char chunk[READ_CHUNK];
    size_t nread;

    table_init(&table);

    while ((nread = fread(chunk, 1, sizeof chunk, stdin)) > 0) {
        size_t i = 0;
        while (i < nread) {
            /* Fast path: a word fully contained in the chunk with no carry-over. */
            if (word.len == 0) {
                while (i < nread && !is_alpha(chunk[i]))
                    i++;
                size_t start = i;
                while (i < nread && is_alpha(chunk[i])) {
                    chunk[i] |= 0x20;
                    i++;
                }
                if (i == start)
                    break;
                if (i < nread) {
                    table_add(&table, (const char *)chunk + start, i - start);
                } else {
                    /* Word may continue in the next chunk. */
                    for (size_t k = start; k < i; k++)
                        buffer_push(&word, (char)chunk[k]);
                }
            } else {
                /* Continue a word carried over from the previous chunk. */
                while (i < nread && is_alpha(chunk[i]))
                    buffer_push(&word, (char)(chunk[i++] | 0x20));
                if (i < nread) {
                    table_add(&table, word.data, word.len);
                    word.len = 0;
                }
            }
        }
    }
    if (ferror(stdin)) {
        perror("wordfreq: read error");
    }
    if (word.len > 0)
        table_add(&table, word.data, word.len);

    const Entry *top[TOP_N];
    size_t n = select_top(&table, top, TOP_N);
    for (size_t i = 0; i < n; i++) {
        printf("%zu ", top[i]->count);
        fwrite(top[i]->word, 1, top[i]->len, stdout);
        putchar('\n');
    }

    free(word.data);
    table_free(&table);
    return fflush(stdout) == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
