/* calc: evaluate one 64-bit integer expression per line of standard input. */
#include "calc.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Read all of stdin into a heap buffer. Returns NULL on failure. */
static char *read_all(FILE *in, size_t *len_out)
{
    size_t cap = 1 << 16, len = 0;
    char *buf = malloc(cap);
    if (!buf)
        return NULL;
    for (;;) {
        if (len == cap) {
            if (cap > SIZE_MAX / 2) {
                free(buf);
                return NULL;
            }
            char *p = realloc(buf, cap * 2);
            if (!p) {
                free(buf);
                return NULL;
            }
            buf = p;
            cap *= 2;
        }
        size_t n = fread(buf + len, 1, cap - len, in);
        len += n;
        if (n == 0) {
            if (ferror(in)) {
                free(buf);
                return NULL;
            }
            break;
        }
    }
    *len_out = len;
    return buf;
}

int main(void)
{
    size_t len = 0;
    char *input = read_all(stdin, &len);
    if (!input) {
        fputs("calc: failed to read input\n", stderr);
        return EXIT_FAILURE;
    }

    static char outbuf[1 << 16];
    setvbuf(stdout, outbuf, _IOFBF, sizeof outbuf);

    calc_ctx ctx = {0};
    int status = EXIT_SUCCESS;
    const char *p = input, *end = input + len;
    while (p < end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        size_t n = nl ? (size_t)(nl - p) : (size_t)(end - p);

        int64_t value;
        calc_status rc = calc_eval(&ctx, p, n, &value);
        if (rc == CALC_OK) {
            printf("%" PRId64 "\n", value);
        } else if (rc == CALC_ERROR) {
            fputs("error\n", stdout);
        } else if (rc == CALC_NOMEM) {
            fputs("calc: out of memory\n", stderr);
            status = EXIT_FAILURE;
            break;
        }
        p += n + 1;
    }

    if (fflush(stdout) != 0)
        status = EXIT_FAILURE;
    calc_ctx_free(&ctx);
    free(input);
    return status;
}
