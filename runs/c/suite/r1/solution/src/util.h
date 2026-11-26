#ifndef SUITE_UTIL_H
#define SUITE_UTIL_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

/* Allocation wrappers: abort the program with a message on exhaustion. */
void *xmalloc(size_t size);
void *xrealloc(void *ptr, size_t size);
void *xcalloc(size_t count, size_t size);
_Noreturn void die(const char *msg);

/* Give stdout a large buffer; call before any output. */
void setup_stdout(void);

/* Smallest power of two >= n (n >= 1). */
size_t next_pow2(size_t n);

/* FNV-1a with a final avalanche so low bits are usable for table indexing. */
static inline uint64_t hash_finish(uint64_t h)
{
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdULL;
    h ^= h >> 33;
    h *= 0xc4ceb9fe1a85ec53ULL;
    h ^= h >> 33;
    return h;
}

#define FNV_OFFSET 0xcbf29ce484222325ULL
#define FNV_PRIME 0x100000001b3ULL

static inline uint64_t hash_bytes(const char *s, size_t len)
{
    uint64_t h = FNV_OFFSET;
    for (size_t i = 0; i < len; i++) {
        h ^= (unsigned char)s[i];
        h *= FNV_PRIME;
    }
    return hash_finish(h);
}

/*
 * Line reader over a FILE*. Yields lines without their terminating '\n';
 * a final line lacking '\n' is still returned. The returned pointer is
 * valid until the next call.
 */
typedef struct {
    FILE *fp;
    char *buf;
    size_t cap;
    size_t start;
    size_t end;
    int eof;
} LineReader;

void line_reader_init(LineReader *lr, FILE *fp);
int line_reader_next(LineReader *lr, const char **line, size_t *len);
void line_reader_free(LineReader *lr);

#endif
