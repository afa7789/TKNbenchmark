#include "util.h"

#include <stdlib.h>
#include <string.h>

#define LINE_READER_INITIAL_CAP ((size_t)64 * 1024)

noreturn void die(const char *msg)
{
    fprintf(stderr, "app: %s\n", msg);
    exit(1);
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

void line_reader_init(LineReader *r, FILE *fp)
{
    r->fp = fp;
    r->cap = LINE_READER_INITIAL_CAP;
    r->buf = xmalloc(r->cap);
    r->pos = 0;
    r->len = 0;
    r->eof = false;
}

void line_reader_free(LineReader *r)
{
    free(r->buf);
    r->buf = NULL;
    r->cap = r->pos = r->len = 0;
}

bool line_reader_next(LineReader *r, const char **line, size_t *len)
{
    size_t scanned = 0; /* bytes after pos already known to hold no '\n' */

    for (;;) {
        char *start = r->buf + r->pos;
        size_t avail = r->len - r->pos;
        char *nl = avail > scanned ? memchr(start + scanned, '\n', avail - scanned) : NULL;

        if (nl) {
            *line = start;
            *len = (size_t)(nl - start);
            r->pos += *len + 1;
            return true;
        }
        if (r->eof) {
            if (avail == 0)
                return false;
            *line = start;
            *len = avail;
            r->pos = r->len;
            return true;
        }
        scanned = avail;

        /* Move the partial line to the front, growing if it fills the buffer. */
        if (r->pos > 0) {
            memmove(r->buf, start, avail);
            r->pos = 0;
            r->len = avail;
        }
        if (r->len == r->cap) {
            r->cap *= 2;
            r->buf = xrealloc(r->buf, r->cap);
        }

        size_t n = fread(r->buf + r->len, 1, r->cap - r->len, r->fp);
        r->len += n;
        if (n == 0)
            r->eof = true;
    }
}
