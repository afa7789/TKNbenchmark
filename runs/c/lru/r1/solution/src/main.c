/*
 * main.c - LRU cache simulator driven by commands on standard input.
 *
 * The whole input is read into memory up front; the cache stores slices
 * into that buffer, so keys and values are never copied.
 */
#include "lru.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- input ---------- */

static char *read_all(FILE *f, size_t *len_out)
{
    size_t cap = 1 << 20, len = 0;
    char *buf = malloc(cap);
    if (!buf)
        return NULL;
    for (;;) {
        if (len == cap) {
            cap *= 2;
            char *grown = realloc(buf, cap);
            if (!grown) {
                free(buf);
                return NULL;
            }
            buf = grown;
        }
        size_t n = fread(buf + len, 1, cap - len, f);
        len += n;
        if (n == 0) {
            if (ferror(f)) {
                free(buf);
                return NULL;
            }
            break;
        }
    }
    *len_out = len;
    return buf;
}

typedef struct {
    const char *cur;
    const char *end;
} line_reader;

/* Return the next line (without '\n' or a trailing '\r'); false at EOF. */
static bool next_line(line_reader *r, lru_slice *line)
{
    if (r->cur >= r->end)
        return false;
    const char *start = r->cur;
    const char *nl = memchr(start, '\n', (size_t)(r->end - start));
    const char *stop = nl ? nl : r->end;
    r->cur = nl ? nl + 1 : r->end;
    if (stop > start && stop[-1] == '\r')
        stop--;
    line->ptr = start;
    line->len = (uint32_t)(stop - start);
    return true;
}

/* Split off the next space-delimited token; false if none remain. */
static bool next_token(lru_slice *rest, lru_slice *tok)
{
    const char *p = rest->ptr, *end = rest->ptr + rest->len;
    while (p < end && *p == ' ')
        p++;
    if (p == end)
        return false;
    const char *q = memchr(p, ' ', (size_t)(end - p));
    if (!q)
        q = end;
    tok->ptr = p;
    tok->len = (uint32_t)(q - p);
    rest->ptr = q;
    rest->len = (uint32_t)(end - q);
    return true;
}

static bool token_is(lru_slice tok, const char *word)
{
    size_t n = strlen(word);
    return tok.len == n && memcmp(tok.ptr, word, n) == 0;
}

static size_t count_lines(const char *buf, size_t len)
{
    size_t n = 1;
    for (const char *p = buf, *end = buf + len;
         (p = memchr(p, '\n', (size_t)(end - p))) != NULL; p++)
        n++;
    return n;
}

/* ---------- output ---------- */

typedef struct {
    char *buf;
    size_t len;
    size_t cap;
} out_buf;

static void out_flush(out_buf *o)
{
    if (o->len) {
        fwrite(o->buf, 1, o->len, stdout);
        o->len = 0;
    }
}

static void out_line(out_buf *o, const char *s, size_t n)
{
    if (o->len + n + 1 > o->cap)
        out_flush(o);
    memcpy(o->buf + o->len, s, n);
    o->len += n;
    o->buf[o->len++] = '\n';
}

static void out_uint(out_buf *o, size_t v)
{
    char tmp[24];
    size_t i = sizeof tmp;
    do {
        tmp[--i] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    out_line(o, tmp + i, sizeof tmp - i);
}

/* ---------- driver ---------- */

static bool parse_capacity(lru_slice line, size_t *out)
{
    lru_slice rest = line, tok;
    if (!next_token(&rest, &tok) || tok.len > 18)
        return false;
    size_t v = 0;
    for (uint32_t i = 0; i < tok.len; i++) {
        if (tok.ptr[i] < '0' || tok.ptr[i] > '9')
            return false;
        v = v * 10 + (size_t)(tok.ptr[i] - '0');
    }
    if (v == 0)
        return false;
    *out = v;
    return true;
}

static void run_command(lru_cache *cache, lru_slice line, out_buf *out)
{
    lru_slice rest = line, cmd, key, value;
    if (!next_token(&rest, &cmd))
        return; /* blank line */

    if (token_is(cmd, "GET")) {
        if (!next_token(&rest, &key))
            return;
        if (lru_get(cache, key, &value))
            out_line(out, value.ptr, value.len);
        else
            out_line(out, "NULL", 4);
    } else if (token_is(cmd, "SET")) {
        if (!next_token(&rest, &key) || !next_token(&rest, &value))
            return;
        lru_set(cache, key, value);
    } else if (token_is(cmd, "DEL")) {
        if (!next_token(&rest, &key))
            return;
        out_line(out, lru_del(cache, key) ? "1" : "0", 1);
    } else if (token_is(cmd, "SIZE")) {
        out_uint(out, lru_size(cache));
    }
    /* Unknown commands are ignored. */
}

int main(void)
{
    size_t len;
    char *input = read_all(stdin, &len);
    if (!input) {
        fprintf(stderr, "lru: failed to read input: %s\n", strerror(errno));
        return 1;
    }

    line_reader reader = { input, input + len };
    lru_slice line;
    size_t capacity;
    if (!next_line(&reader, &line) || !parse_capacity(line, &capacity)) {
        free(input);
        return 0; /* nothing to simulate */
    }

    lru_cache *cache = lru_create(capacity, count_lines(input, len));
    out_buf out = { malloc(1 << 16), 0, 1 << 16 };
    if (!cache || !out.buf) {
        fprintf(stderr, "lru: out of memory\n");
        lru_destroy(cache);
        free(out.buf);
        free(input);
        return 1;
    }

    while (next_line(&reader, &line))
        run_command(cache, line, &out);

    out_flush(&out);
    fflush(stdout);
    free(out.buf);
    lru_destroy(cache);
    free(input);
    return 0;
}
