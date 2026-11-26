#include "util.h"

#include <stdlib.h>
#include <string.h>

_Noreturn void die(const char *msg)
{
    fprintf(stderr, "app: %s\n", msg);
    exit(EXIT_FAILURE);
}

void *xmalloc(size_t size)
{
    void *p = malloc(size ? size : 1);
    if (!p)
        die("out of memory");
    return p;
}

void *xrealloc(void *ptr, size_t size)
{
    void *p = realloc(ptr, size ? size : 1);
    if (!p)
        die("out of memory");
    return p;
}

void *xcalloc(size_t count, size_t size)
{
    void *p = calloc(count ? count : 1, size ? size : 1);
    if (!p)
        die("out of memory");
    return p;
}

void setup_stdout(void)
{
    static char outbuf[1 << 16];
    setvbuf(stdout, outbuf, _IOFBF, sizeof outbuf);
}

size_t next_pow2(size_t n)
{
    size_t p = 1;
    while (p < n)
        p <<= 1;
    return p;
}

enum { LINE_READER_INITIAL = 1 << 16 };

void line_reader_init(LineReader *lr, FILE *fp)
{
    lr->fp = fp;
    lr->cap = LINE_READER_INITIAL;
    lr->buf = xmalloc(lr->cap);
    lr->start = 0;
    lr->end = 0;
    lr->eof = 0;
}

void line_reader_free(LineReader *lr)
{
    free(lr->buf);
    lr->buf = NULL;
}

/* Make room after the unconsumed data and read more of the stream. */
static void line_reader_fill(LineReader *lr)
{
    size_t pending = lr->end - lr->start;
    if (lr->start > 0) {
        memmove(lr->buf, lr->buf + lr->start, pending);
        lr->start = 0;
        lr->end = pending;
    }
    if (lr->end == lr->cap) {
        lr->cap *= 2;
        lr->buf = xrealloc(lr->buf, lr->cap);
    }
    size_t got = fread(lr->buf + lr->end, 1, lr->cap - lr->end, lr->fp);
    if (got == 0) {
        if (ferror(lr->fp))
            die("read error on standard input");
        lr->eof = 1;
    }
    lr->end += got;
}

int line_reader_next(LineReader *lr, const char **line, size_t *len)
{
    size_t scanned = 0;
    for (;;) {
        char *base = lr->buf + lr->start;
        size_t avail = lr->end - lr->start;
        char *nl = memchr(base + scanned, '\n', avail - scanned);
        if (nl) {
            *line = base;
            *len = (size_t)(nl - base);
            lr->start += *len + 1;
            return 1;
        }
        if (lr->eof) {
            if (avail == 0)
                return 0;
            *line = base;
            *len = avail;
            lr->start = lr->end;
            return 1;
        }
        scanned = avail;
        line_reader_fill(lr);
    }
}
