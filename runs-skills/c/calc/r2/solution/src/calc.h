#ifndef CALC_CALC_H
#define CALC_CALC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    CALC_OK,      /* expression evaluated; result stored */
    CALC_BLANK,   /* line is empty or whitespace only */
    CALC_ERROR,   /* syntax error, division by zero or overflow */
    CALC_NOMEM    /* allocation failure */
} calc_status;

/* Reusable evaluation workspace; zero-initialize before first use. */
typedef struct {
    int64_t *vals;
    unsigned char *ops;
    size_t cap;
} calc_ctx;

/* Evaluate the expression in s[0..len). Does not require NUL termination. */
calc_status calc_eval(calc_ctx *ctx, const char *s, size_t len, int64_t *out);

void calc_ctx_free(calc_ctx *ctx);

#ifdef __cplusplus
}
#endif

#endif
