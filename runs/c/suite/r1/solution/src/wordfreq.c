/*
 * wordfreq: count case-folded runs of ASCII letters and print the ten most
 * frequent, by count descending then word ascending.
 *
 * Input is streamed in chunks; a word cut off at the end of a chunk is moved
 * to the front of the buffer and completed by the next read. Distinct words
 * are copied into an arena and indexed by an open-addressing hash table.
 */
#include "commands.h"
#include "util.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    CHUNK_SIZE = 1 << 20,
    ARENA_BLOCK = 1 << 20,
    TABLE_INITIAL = 1 << 12,
    TOP_N = 10,
};

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
} WordTable;

typedef struct ArenaBlock {
    struct ArenaBlock *next;
    size_t used;
    size_t cap;
    char data[];
} ArenaBlock;

typedef struct {
    ArenaBlock *head;
} Arena;

static const char *arena_copy(Arena *a, const char *s, size_t len)
{
    ArenaBlock *b = a->head;
    if (!b || b->cap - b->used < len) {
        size_t cap = len > ARENA_BLOCK ? len : ARENA_BLOCK;
        b = xmalloc(sizeof *b + cap);
        b->next = a->head;
        b->used = 0;
        b->cap = cap;
        a->head = b;
    }
    char *dst = b->data + b->used;
    memcpy(dst, s, len);
    b->used += len;
    return dst;
}

static void arena_free(Arena *a)
{
    while (a->head) {
        ArenaBlock *next = a->head->next;
        free(a->head);
        a->head = next;
    }
}

static void table_grow(WordTable *t)
{
    size_t new_cap = t->cap * 2;
    Entry *slots = xcalloc(new_cap, sizeof *slots);
    size_t mask = new_cap - 1;
    for (size_t i = 0; i < t->cap; i++) {
        const Entry *e = &t->slots[i];
        if (!e->word)
            continue;
        size_t j = e->hash & mask;
        while (slots[j].word)
            j = (j + 1) & mask;
        slots[j] = *e;
    }
    free(t->slots);
    t->slots = slots;
    t->cap = new_cap;
}

/* Count one occurrence of an already lowercased word. */
static void table_add(WordTable *t, Arena *arena, const char *word, size_t len, uint64_t hash)
{
    size_t mask = t->cap - 1;
    size_t i = hash & mask;
    for (;;) {
        Entry *e = &t->slots[i];
        if (!e->word)
            break;
        if (e->hash == hash && e->len == len && memcmp(e->word, word, len) == 0) {
            e->count++;
            return;
        }
        i = (i + 1) & mask;
    }
    t->slots[i] = (Entry){arena_copy(arena, word, len), len, hash, 1};
    if (++t->used * 4 > t->cap * 3)
        table_grow(t);
}

static bool is_letter(unsigned char c)
{
    return (unsigned char)((c | 0x20) - 'a') < 26;
}

/*
 * Fold and count every complete word in buf[0, len). When `final` is false,
 * a word touching the end may continue in the next chunk; its start offset
 * is returned so the caller can carry it over. Otherwise returns len.
 */
static size_t count_words(WordTable *t, Arena *arena, char *buf, size_t len, bool final)
{
    size_t i = 0;
    while (i < len) {
        if (!is_letter((unsigned char)buf[i])) {
            i++;
            continue;
        }
        size_t start = i;
        uint64_t h = FNV_OFFSET;
        while (i < len && is_letter((unsigned char)buf[i])) {
            char c = (char)(buf[i] | 0x20);
            buf[i] = c;
            h = (h ^ (unsigned char)c) * FNV_PRIME;
            i++;
        }
        if (i == len && !final)
            return start;
        table_add(t, arena, buf + start, i - start, hash_finish(h));
    }
    return len;
}

/* Order: count descending, then word ascending by bytes. */
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

static void print_top(const WordTable *t)
{
    const Entry *top[TOP_N];
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
    for (size_t i = 0; i < n; i++)
        printf("%llu %.*s\n", (unsigned long long)top[i]->count, (int)top[i]->len, top[i]->word);
}

int cmd_wordfreq(void)
{
    WordTable table = {xcalloc(TABLE_INITIAL, sizeof(Entry)), TABLE_INITIAL, 0};
    Arena arena = {NULL};
    size_t cap = CHUNK_SIZE;
    char *buf = xmalloc(cap);
    size_t carry = 0;

    for (;;) {
        /* Keep each read at least as large as the carried-over word so a
         * very long word is not rescanned a quadratic number of times. */
        if (cap - carry < CHUNK_SIZE / 2 || cap - carry < carry) {
            while (cap - carry < CHUNK_SIZE / 2 || cap - carry < carry)
                cap *= 2;
            buf = xrealloc(buf, cap);
        }
        size_t got = fread(buf + carry, 1, cap - carry, stdin);
        if (got == 0 && ferror(stdin))
            die("read error on standard input");
        size_t len = carry + got;
        bool final = got == 0;
        size_t rest = count_words(&table, &arena, buf, len, final);
        if (final)
            break;
        carry = len - rest;
        memmove(buf, buf + rest, carry);
    }

    print_top(&table);
    free(buf);
    free(table.slots);
    arena_free(&arena);
    return 0;
}
