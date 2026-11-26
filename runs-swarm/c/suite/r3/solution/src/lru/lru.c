/* lru: LRU cache simulator. See the "lru" section of SPEC.md. */

#include "lru/lru.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lru/cache.h"

#define CAPACITY_MAX 1000000u
#define TOKEN_MAX 64u
#define MAX_TOKENS 3

struct buffer {
    char *data;
    size_t len;
};

/*
 * Reads all of `in` into memory. The cache refers to keys and values in
 * place, so the whole input must outlive it. Returns false on a read or
 * allocation failure.
 */
static bool read_all(FILE *in, struct buffer *buf)
{
    size_t cap = 1 << 16;
    size_t len = 0;
    char *data = malloc(cap);
    if (!data)
        return false;

    for (;;) {
        if (len == cap) {
            char *grown = realloc(data, cap * 2);
            if (!grown) {
                free(data);
                return false;
            }
            data = grown;
            cap *= 2;
        }
        size_t n = fread(data + len, 1, cap - len, in);
        len += n;
        if (n == 0) {
            if (ferror(in)) {
                free(data);
                return false;
            }
            break;
        }
    }
    buf->data = data;
    buf->len = len;
    return true;
}

struct token {
    const char *s;
    size_t len;
};

/* Splits [s, s+len) on single spaces. Returns the token count, or -1 if
 * there are more than `max` tokens or any token is empty. */
static int split(const char *s, size_t len, struct token *tok, int max)
{
    int n = 0;
    const char *end = s + len;
    for (;;) {
        const char *sp = memchr(s, ' ', (size_t)(end - s));
        const char *stop = sp ? sp : end;
        if (stop == s || n == max)
            return -1;
        tok[n].s = s;
        tok[n].len = (size_t)(stop - s);
        n++;
        if (!sp)
            return n;
        s = sp + 1;
    }
}

static bool token_is(const struct token *t, const char *word)
{
    size_t len = strlen(word);
    return t->len == len && memcmp(t->s, word, len) == 0;
}

static bool parse_capacity(const char *s, size_t len, size_t *out)
{
    if (len == 0)
        return false;
    size_t v = 0;
    for (size_t i = 0; i < len; i++) {
        if (s[i] < '0' || s[i] > '9')
            return false;
        v = v * 10 + (size_t)(s[i] - '0');
        if (v > CAPACITY_MAX)
            return false;
    }
    if (v < 1)
        return false;
    *out = v;
    return true;
}

/* Returns the next line of [*pos, end) without its terminator ("\n" or
 * "\r\n") and advances *pos past it. */
static struct token next_line(const char **pos, const char *end)
{
    const char *s = *pos;
    const char *nl = memchr(s, '\n', (size_t)(end - s));
    const char *stop = nl ? nl : end;
    *pos = nl ? nl + 1 : end;
    if (stop > s && stop[-1] == '\r')
        stop--;
    return (struct token){ s, (size_t)(stop - s) };
}

/* Executes one command line, writing its output to `out`. Returns false if
 * the line is malformed. */
static bool run_command(struct lru_cache *cache, struct token line, FILE *out,
                        bool *oom)
{
    struct token tok[MAX_TOKENS];
    int n = split(line.s, line.len, tok, MAX_TOKENS);
    if (n < 1)
        return false;
    for (int i = 1; i < n; i++) {
        if (tok[i].len > TOKEN_MAX)
            return false;
    }

    if (n == 3 && token_is(&tok[0], "SET")) {
        if (!lru_cache_set(cache, tok[1].s, tok[1].len, tok[2].s, tok[2].len))
            *oom = true;
    } else if (n == 2 && token_is(&tok[0], "GET")) {
        const char *value;
        size_t value_len;
        if (lru_cache_get(cache, tok[1].s, tok[1].len, &value, &value_len)) {
            fwrite(value, 1, value_len, out);
            putc('\n', out);
        } else {
            fputs("NULL\n", out);
        }
    } else if (n == 2 && token_is(&tok[0], "DEL")) {
        fputs(lru_cache_del(cache, tok[1].s, tok[1].len) ? "1\n" : "0\n", out);
    } else if (n == 1 && token_is(&tok[0], "SIZE")) {
        fprintf(out, "%zu\n", lru_cache_size(cache));
    } else {
        return false;
    }
    return true;
}

int lru_main(int argc, char **argv)
{
    if (argc != 1) {
        fprintf(stderr, "usage: %s < input\n", argv[0]);
        return 2;
    }

    struct buffer input;
    if (!read_all(stdin, &input)) {
        fprintf(stderr, "%s: cannot read standard input\n", argv[0]);
        return 1;
    }

    const char *pos = input.data;
    const char *end = input.data + input.len;
    struct token first = next_line(&pos, end);
    size_t capacity;
    if (!parse_capacity(first.s, first.len, &capacity)) {
        fprintf(stderr, "%s: line 1: invalid capacity\n", argv[0]);
        free(input.data);
        return 1;
    }

    struct lru_cache cache;
    if (!lru_cache_init(&cache, capacity)) {
        fprintf(stderr, "%s: out of memory\n", argv[0]);
        free(input.data);
        return 1;
    }

    static char outbuf[1 << 16];
    setvbuf(stdout, outbuf, _IOFBF, sizeof outbuf);

    int status = 0;
    bool oom = false;
    for (size_t lineno = 2; pos < end && !oom; lineno++) {
        struct token line = next_line(&pos, end);
        if (line.len == 0)
            continue;
        if (!run_command(&cache, line, stdout, &oom))
            fprintf(stderr, "%s: line %zu: invalid command ignored\n",
                    argv[0], lineno);
    }
    if (oom) {
        fprintf(stderr, "%s: out of memory\n", argv[0]);
        status = 1;
    }
    if (fflush(stdout) != 0) {
        fprintf(stderr, "%s: write error\n", argv[0]);
        status = 1;
    }

    lru_cache_destroy(&cache);
    free(input.data);
    return status;
}
