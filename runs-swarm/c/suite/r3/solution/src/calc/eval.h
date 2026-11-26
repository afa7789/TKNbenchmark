/* Expression evaluator for calc: parses and evaluates one line. */
#ifndef CALC_EVAL_H
#define CALC_EVAL_H

#include <stddef.h>
#include <stdint.h>

enum calc_status {
    CALC_OK,     /* the expression has a value */
    CALC_BLANK,  /* the line holds only spaces and tabs */
    CALC_ERROR,  /* syntax error, division by zero or overflow */
    CALC_NOMEM,  /* out of memory */
};

/*
 * Evaluator state. The operand and operator stacks are kept between calls so
 * that their storage is reused; nesting depth is limited only by memory.
 * Initialise with CALC_EVALUATOR_INIT and release with calc_evaluator_free().
 */
struct calc_evaluator {
    int64_t *vals;
    size_t nvals, vals_cap;
    unsigned char *ops;
    size_t nops, ops_cap;
};

#define CALC_EVALUATOR_INIT { NULL, 0, 0, NULL, 0, 0 }

/*
 * Evaluates the len bytes at line (which need not be NUL-terminated and must
 * not contain the line terminator). On CALC_OK stores the value in *result.
 */
enum calc_status calc_eval(struct calc_evaluator *ev, const char *line,
                           size_t len, int64_t *result);

void calc_evaluator_free(struct calc_evaluator *ev);

#endif
