#ifndef SUITE_UTIL_H
#define SUITE_UTIL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdnoreturn.h>

/* Print "app: <msg>" to stderr and exit with status 1. */
noreturn void die(const char *msg);

/* Allocation wrappers that abort the program on failure. */
void *xmalloc(size_t size);
void *xrealloc(void *ptr, size_t size);
void *xcalloc(size_t count, size_t size);

/*
 * Buffered reader that yields one line at a time, without its terminating
 * '\n'. A final line lacking '\n' is still returned. Lines may be of any
 * length; the internal buffer grows as needed.
 */
typedef struct {
    FILE *fp;
    char *buf;
    size_t cap;
    size_t pos; /* start of unconsumed data */
    size_t len; /* end of valid data */
    bool eof;
} LineReader;

void line_reader_init(LineReader *r, FILE *fp);
void line_reader_free(LineReader *r);

/*
 * Fetch the next line. On success stores a pointer to it (valid until the
 * next call) and its length, and returns true. Returns false at end of input.
 */
bool line_reader_next(LineReader *r, const char **line, size_t *len);

#endif
