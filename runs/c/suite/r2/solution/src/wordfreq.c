/* wordfreq: print the 10 most frequent ASCII-letter words of stdin. */
#include "commands.h"
#include "hash.h"
#include "io.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

enum { TOP_N = 10 };

/* Words point into the (lowercased in place) input buffer; no copies. */
typedef struct {
    const char *word; /* NULL marks an empty slot */
    size_t len;
    uint64_t hash;
    uint64_t count;
} Entry;

typedef struct {
    Entry *slots;
    size_t cap; /* power of two */
    size_t used;
} Table;

static void table_init(Table *t, size_t cap)
{
    t->slots = xcalloc(cap, sizeof *t->slots);
    t->cap = cap;
    t->used = 0;
}

static void table_grow(Table *t)
{
    Table bigger;
    table_init(&bigger, t->cap * 2);
    size_t mask = bigger.cap - 1;
    for (size_t i = 0; i < t->cap; i++) {
        const Entry *e = &t->slots[i];
        if (!e->word)
            continue;
        size_t j = e->hash & mask;
        while (bigger.slots[j].word)
            j = (j + 1) & mask;
        bigger.slots[j] = *e;
    }
    bigger.used = t->used;
    free(t->slots);
    *t = bigger;
}

static void table_add(Table *t, const char *word, size_t len)
{
    uint64_t h = hash_bytes(word, len);
    size_t mask = t->cap - 1;
    size_t i = h & mask;
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
    t->slots[i] = (Entry){ .word = word, .len = len, .hash = h, .count = 1 };
    if (++t->used * 4 > t->cap * 3)
        table_grow(t);
}

/* Byte-order comparison of two words; a proper prefix sorts first. */
static int word_cmp(const Entry *a, const Entry *b)
{
    size_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->word, b->word, n);
    if (c)
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

static inline bool is_alpha(unsigned char c)
{
    return (unsigned char)((c | 0x20) - 'a') < 26;
}

int cmd_wordfreq(void)
{
    Input in = input_read_all(stdin);
    Table table;
    table_init(&table, 1 << 12);

    unsigned char *p = (unsigned char *)in.data;
    unsigned char *end = p + in.len;
    while (p < end) {
        if (!is_alpha(*p)) {
            p++;
            continue;
        }
        unsigned char *start = p;
        do {
            *p |= 0x20; /* ASCII lowercase */
            p++;
        } while (p < end && is_alpha(*p));
        table_add(&table, (const char *)start, (size_t)(p - start));
    }

    /* Partial selection: keep the best TOP_N entries in sorted order. */
    const Entry *top[TOP_N];
    size_t ntop = 0;
    for (size_t i = 0; i < table.cap; i++) {
        const Entry *e = &table.slots[i];
        if (!e->word)
            continue;
        if (ntop == TOP_N && !ranks_before(e, top[TOP_N - 1]))
            continue;
        size_t j = ntop < TOP_N ? ntop++ : TOP_N - 1;
        while (j > 0 && ranks_before(e, top[j - 1])) {
            top[j] = top[j - 1];
            j--;
        }
        top[j] = e;
    }

    Output out;
    out_init(&out, stdout);
    for (size_t i = 0; i < ntop; i++) {
        out_u64(&out, top[i]->count);
        out_char(&out, ' ');
        out_write(&out, top[i]->word, top[i]->len);
        out_char(&out, '\n');
    }
    out_finish(&out);

    free(table.slots);
    input_free(&in);
    return EXIT_SUCCESS;
}
