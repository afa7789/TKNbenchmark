/* calc: 64-bit integer expression evaluator. See the "calc" section of SPEC.md. */

#include "calc/calc.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "calc/eval.h"

enum { READ_CHUNK = 64 * 1024 };

/*
 * Buffered line reader over a stream. Lines may be arbitrarily long; the
 * buffer grows to hold the longest one.
 */
struct line_reader {
    FILE *fp;
    char *buf;
    size_t cap;
    size_t start;  /* first unconsumed byte */
    size_t end;    /* one past the last byte read */
    size_t scan;   /* bytes in [start, scan) are known to hold no '\n' */
    bool eof;
};

/* Ensures at least READ_CHUNK bytes of free space after buf[end]. */
static bool reader_make_room(struct line_reader *r)
{
    if (r->start > 0) {
        size_t n = r->end - r->start;
        memmove(r->buf, r->buf + r->start, n);
        r->scan -= r->start;
        r->end = n;
        r->start = 0;
    }
    if (r->cap - r->end >= READ_CHUNK)
        return true;

    size_t new_cap = r->cap ? r->cap : READ_CHUNK;
    while (new_cap - r->end < READ_CHUNK) {
        if (new_cap > SIZE_MAX / 2)
            return false;
        new_cap *= 2;
    }
    char *p = realloc(r->buf, new_cap);
    if (!p)
        return false;
    r->buf = p;
    r->cap = new_cap;
    return true;
}

/*
 * Reads the next line, without its '\n', into *line / *len. Returns 1 on
 * success, 0 at end of input and -1 on a read or allocation error.
 */
static int reader_next(struct line_reader *r, const char **line, size_t *len)
{
    for (;;) {
        char *nl = r->scan < r->end
                       ? memchr(r->buf + r->scan, '\n', r->end - r->scan)
                       : NULL;
        if (nl) {
            size_t pos = (size_t)(nl - r->buf);
            *line = r->buf + r->start;
            *len = pos - r->start;
            r->start = r->scan = pos + 1;
            return 1;
        }
        r->scan = r->end;

        if (r->eof) {
            if (r->start == r->end)
                return 0;
            *line = r->buf + r->start; /* final line without '\n' */
            *len = r->end - r->start;
            r->start = r->scan = r->end;
            return 1;
        }

        if (!reader_make_room(r))
            return -1;
        size_t n = fread(r->buf + r->end, 1, r->cap - r->end, r->fp);
        r->end += n;
        if (n == 0) {
            if (ferror(r->fp))
                return -1;
            r->eof = true;
        }
    }
}

int calc_main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    static char outbuf[64 * 1024];
    setvbuf(stdout, outbuf, _IOFBF, sizeof outbuf);

    struct line_reader reader = { .fp = stdin };
    struct calc_evaluator ev = CALC_EVALUATOR_INIT;
    const char *line;
    size_t len;
    int status = 0;
    int rc;

    while ((rc = reader_next(&reader, &line, &len)) > 0) {
        int64_t value;
        enum calc_status st = calc_eval(&ev, line, len, &value);
        if (st == CALC_OK) {
            printf("%" PRId64 "\n", value);
        } else if (st == CALC_ERROR) {
            fputs("error\n", stdout);
        } else if (st == CALC_NOMEM) {
            fputs("calc: out of memory\n", stderr);
            status = 1;
            break;
        }
    }
    if (rc < 0) {
        fputs(ferror(stdin) ? "calc: read error\n" : "calc: out of memory\n", stderr);
        status = 1;
    }

    calc_evaluator_free(&ev);
    free(reader.buf);

    if (fflush(stdout) == EOF || ferror(stdout)) {
        fputs("calc: write error\n", stderr);
        status = 1;
    }
    return status;
}
