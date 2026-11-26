#include "io.h"

#include <stdlib.h>
#include <string.h>

static void die(const char *what)
{
    perror(what);
    exit(EXIT_FAILURE);
}

void *xmalloc(size_t n)
{
    void *p = malloc(n ? n : 1);
    if (!p)
        die("malloc");
    return p;
}

void *xcalloc(size_t count, size_t size)
{
    void *p = calloc(count ? count : 1, size ? size : 1);
    if (!p)
        die("calloc");
    return p;
}

void *xrealloc(void *p, size_t n)
{
    void *q = realloc(p, n ? n : 1);
    if (!q)
        die("realloc");
    return q;
}

Input input_read_all(FILE *stream)
{
    size_t cap = 1 << 16;
    size_t len = 0;
    char *data = xmalloc(cap);

    for (;;) {
        if (cap - len < 2) {
            cap *= 2;
            data = xrealloc(data, cap);
        }
        size_t got = fread(data + len, 1, cap - len - 1, stream);
        len += got;
        if (got == 0) {
            if (ferror(stream))
                die("read");
            break;
        }
    }
    data[len] = '\0';
    return (Input){ .data = data, .len = len };
}

void input_free(Input *in)
{
    free(in->data);
    in->data = NULL;
    in->len = 0;
}

enum { OUT_CAP = 1 << 16 };

void out_init(Output *out, FILE *stream)
{
    out->stream = stream;
    out->buf = xmalloc(OUT_CAP);
    out->len = 0;
    out->cap = OUT_CAP;
}

static void out_drain(Output *out)
{
    if (out->len && fwrite(out->buf, 1, out->len, out->stream) != out->len)
        die("write");
    out->len = 0;
}

void out_write(Output *out, const char *s, size_t n)
{
    if (n > out->cap - out->len) {
        out_drain(out);
        if (n > out->cap) {
            if (fwrite(s, 1, n, out->stream) != n)
                die("write");
            return;
        }
    }
    memcpy(out->buf + out->len, s, n);
    out->len += n;
}

void out_char(Output *out, char c)
{
    if (out->len == out->cap)
        out_drain(out);
    out->buf[out->len++] = c;
}

void out_cstr(Output *out, const char *s)
{
    out_write(out, s, strlen(s));
}

void out_u64(Output *out, uint64_t v)
{
    char tmp[20];
    size_t i = sizeof tmp;
    do {
        tmp[--i] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    out_write(out, tmp + i, sizeof tmp - i);
}

void out_i64(Output *out, int64_t v)
{
    if (v < 0) {
        out_char(out, '-');
        /* Negate in unsigned arithmetic so INT64_MIN is handled. */
        out_u64(out, (uint64_t)0 - (uint64_t)v);
    } else {
        out_u64(out, (uint64_t)v);
    }
}

void out_finish(Output *out)
{
    out_drain(out);
    if (fflush(out->stream) != 0)
        die("write");
    free(out->buf);
    out->buf = NULL;
}
