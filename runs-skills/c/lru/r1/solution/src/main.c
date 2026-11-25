/* lru: simulate an LRU cache driven by commands on standard input. */
#include "lru.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CAPACITY_MAX 1000000u

typedef struct {
    char *data;
    size_t len;
} buffer;

static int read_all(FILE *in, buffer *out)
{
    size_t cap = 1 << 16, len = 0;
    char *data = malloc(cap);
    if (!data)
        return ENOMEM;
    for (;;) {
        if (len == cap) {
            if (cap > SIZE_MAX / 2) {
                free(data);
                return ENOMEM;
            }
            char *p = realloc(data, cap * 2);
            if (!p) {
                free(data);
                return ENOMEM;
            }
            data = p;
            cap *= 2;
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

/* Buffered stdout writer. */
typedef struct {
    char buf[1 << 16];
    size_t len;
    FILE *f;
} writer;

static void w_flush(writer *w)
{
    if (w->len)
        fwrite(w->buf, 1, w->len, w->f);
    w->len = 0;
}

static void w_line(writer *w, const char *s, size_t n)
{
    if (sizeof w->buf - w->len < n + 1)
        w_flush(w);
    memcpy(w->buf + w->len, s, n);
    w->len += n;
    w->buf[w->len++] = '\n';
}

static void w_size(writer *w, size_t v)
{
    char tmp[24];
    int n = snprintf(tmp, sizeof tmp, "%zu", v);
    w_line(w, tmp, (size_t)n);
}

/* Split off the next space-delimited token from *rest (within a line). */
static lru_str next_token(lru_str *rest)
{
    const char *p = rest->data;
    const char *sp = memchr(p, ' ', rest->len);
    size_t n = sp ? (size_t)(sp - p) : rest->len;
    lru_str tok = {p, n};
    rest->data = p + (sp ? n + 1 : n);
    rest->len -= sp ? n + 1 : n;
    return tok;
}

static bool tok_is(lru_str t, const char *lit)
{
    size_t n = strlen(lit);
    return t.len == n && memcmp(t.data, lit, n) == 0;
}

static bool parse_capacity(lru_str s, size_t *out)
{
    size_t v = 0;
    if (s.len == 0)
        return false;
    for (size_t i = 0; i < s.len; i++) {
        unsigned d = (unsigned char)s.data[i] - '0';
        if (d > 9)
            return false;
        v = v * 10 + d;
        if (v > CAPACITY_MAX)
            return false;
    }
    if (v == 0)
        return false;
    *out = v;
    return true;
}

/* Fetch the next line from the input, without its terminator (and a trailing
 * CR, if any). Returns false at end of input. */
static bool next_line(const buffer *in, size_t *pos, lru_str *line)
{
    if (*pos >= in->len)
        return false;
    const char *start = in->data + *pos;
    size_t avail = in->len - *pos;
    const char *nl = memchr(start, '\n', avail);
    size_t n = nl ? (size_t)(nl - start) : avail;
    *pos += nl ? n + 1 : n;
    if (n && start[n - 1] == '\r')
        n--;
    *line = (lru_str){start, n};
    return true;
}

int main(void)
{
    buffer in;
    int err = read_all(stdin, &in);
    if (err) {
        fprintf(stderr, "lru: reading input: %s\n", strerror(err));
        return EXIT_FAILURE;
    }

    size_t pos = 0, capacity;
    lru_str line;
    if (!next_line(&in, &pos, &line) || !parse_capacity(line, &capacity)) {
        fprintf(stderr, "lru: first line must be a capacity in 1..%u\n", CAPACITY_MAX);
        free(in.data);
        return EXIT_FAILURE;
    }

    lru_cache *cache = lru_create(capacity);
    if (!cache) {
        fprintf(stderr, "lru: out of memory\n");
        free(in.data);
        return EXIT_FAILURE;
    }

    static writer out;
    out.f = stdout;
    int status = EXIT_SUCCESS;

    while (next_line(&in, &pos, &line)) {
        lru_str rest = line;
        lru_str cmd = next_token(&rest);
        if (tok_is(cmd, "SET")) {
            lru_str key = next_token(&rest);
            lru_str value = next_token(&rest);
            if (lru_set(cache, key, value) != 0) {
                fprintf(stderr, "lru: out of memory\n");
                status = EXIT_FAILURE;
                break;
            }
        } else if (tok_is(cmd, "GET")) {
            lru_str value;
            if (lru_get(cache, next_token(&rest), &value))
                w_line(&out, value.data, value.len);
            else
                w_line(&out, "NULL", 4);
        } else if (tok_is(cmd, "DEL")) {
            w_line(&out, lru_del(cache, next_token(&rest)) ? "1" : "0", 1);
        } else if (tok_is(cmd, "SIZE")) {
            w_size(&out, lru_size(cache));
        }
        /* Blank or unrecognised lines are ignored. */
    }

    w_flush(&out);
    if (fflush(stdout) != 0 || ferror(stdout))
        status = EXIT_FAILURE;
    lru_destroy(cache);
    free(in.data);
    return status;
}
