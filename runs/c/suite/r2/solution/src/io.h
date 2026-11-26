#ifndef SUITE_IO_H
#define SUITE_IO_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

/* A heap buffer holding an entire input stream. data is NUL-terminated
 * (the terminator is not counted in len) so scanners may use a sentinel. */
typedef struct {
    char *data;
    size_t len;
} Input;

/* Read all of stream into memory. Exits with a diagnostic on failure. */
Input input_read_all(FILE *stream);
void input_free(Input *in);

/* Buffered writer over a FILE*, flushed when full and on out_flush(). */
typedef struct {
    FILE *stream;
    char *buf;
    size_t len;
    size_t cap;
} Output;

void out_init(Output *out, FILE *stream);
void out_write(Output *out, const char *s, size_t n);
void out_char(Output *out, char c);
void out_cstr(Output *out, const char *s);
void out_i64(Output *out, int64_t v);
void out_u64(Output *out, uint64_t v);
/* Flush and release the buffer. */
void out_finish(Output *out);

/* Allocation helpers that abort the program on failure. */
void *xmalloc(size_t n);
void *xcalloc(size_t count, size_t size);
void *xrealloc(void *p, size_t n);

#endif
