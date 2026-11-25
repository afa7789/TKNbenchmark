#include "calc.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Read all of stream into a heap buffer. Returns NULL on error. */
static char *read_all(FILE *fp, size_t *len)
{
    size_t cap = 1 << 16, n = 0;
    char *buf = malloc(cap);
    if (!buf)
        return NULL;
    for (;;) {
        if (n == cap) {
            if (cap > SIZE_MAX / 2)
                goto fail;
            char *p = realloc(buf, cap * 2);
            if (!p)
                goto fail;
            buf = p;
            cap *= 2;
        }
        size_t got = fread(buf + n, 1, cap - n, fp);
        n += got;
        if (got == 0) {
            if (ferror(fp))
                goto fail;
            break;
        }
    }
    *len = n;
    return buf;
fail:
    free(buf);
    return NULL;
}

int main(void)
{
    size_t len = 0;
    char *input = read_all(stdin, &len);
    if (!input) {
        fputs("calc: failed to read input\n", stderr);
        return EXIT_FAILURE;
    }

    calc_ctx ctx = {0};
    int status = EXIT_SUCCESS;
    const char *p = input, *end = input + len;
    while (p < end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        size_t n = nl ? (size_t)(nl - p) : (size_t)(end - p);

        int64_t value;
        switch (calc_eval(&ctx, p, n, &value)) {
        case CALC_OK:
            printf("%" PRId64 "\n", value);
            break;
        case CALC_ERROR:
            fputs("error\n", stdout);
            break;
        case CALC_EMPTY:
            break;
        case CALC_NOMEM:
            fputs("calc: out of memory\n", stderr);
            status = EXIT_FAILURE;
            goto out;
        }
        p += n + 1;
    }

out:
    calc_ctx_free(&ctx);
    free(input);
    if (fflush(stdout) != 0)
        status = EXIT_FAILURE;
    return status;
}
