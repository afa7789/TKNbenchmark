/*
 * Operator-precedence (shunting-yard) evaluator for the calc grammar:
 *
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *
 * Explicit stacks are used instead of recursion so that deeply nested input
 * cannot overflow the call stack. Operators are applied as soon as they are
 * reduced, so evaluation stops at the first error.
 */

#include "calc/eval.h"

#include <stdbool.h>
#include <stdlib.h>

/* Operator stack entries. Binary operators are stored as their character. */
enum {
    OP_LPAREN = '(',
    OP_NEG = 'n',
};

static int precedence(unsigned char op)
{
    switch (op) {
    case '+': case '-':           return 1;
    case '*': case '/': case '%': return 2;
    case OP_NEG:                  return 3;
    default:                      return 0; /* '(' is never reduced past */
    }
}

/* Overflow-checked arithmetic. Each returns false if the result is undefined. */

static bool checked_add(int64_t a, int64_t b, int64_t *r)
{
    if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b))
        return false;
    *r = a + b;
    return true;
}

static bool checked_sub(int64_t a, int64_t b, int64_t *r)
{
    if ((b < 0 && a > INT64_MAX + b) || (b > 0 && a < INT64_MIN + b))
        return false;
    *r = a - b;
    return true;
}

static bool checked_mul(int64_t a, int64_t b, int64_t *r)
{
    if (a > 0) {
        if (b > 0 ? a > INT64_MAX / b : b < INT64_MIN / a)
            return false;
    } else if (a < 0) {
        if (b > 0 ? a < INT64_MIN / b : b < INT64_MAX / a)
            return false;
    }
    *r = a * b;
    return true;
}

static bool checked_div(int64_t a, int64_t b, int64_t *r)
{
    if (b == 0 || (a == INT64_MIN && b == -1))
        return false;
    *r = a / b;
    return true;
}

static bool checked_rem(int64_t a, int64_t b, int64_t *r)
{
    if (b == 0)
        return false;
    *r = b == -1 ? 0 : a % b; /* INT64_MIN % -1 is undefined in C but 0 here */
    return true;
}

static bool checked_neg(int64_t a, int64_t *r)
{
    if (a == INT64_MIN)
        return false;
    *r = -a;
    return true;
}

/* Grows *buf (of elements of size elem) so that it can hold one more item. */
static bool reserve_one(void **buf, size_t *cap, size_t n, size_t elem)
{
    if (n < *cap)
        return true;
    size_t new_cap = *cap ? *cap * 2 : 64;
    if (new_cap > SIZE_MAX / elem)
        return false;
    void *p = realloc(*buf, new_cap * elem);
    if (!p)
        return false;
    *buf = p;
    *cap = new_cap;
    return true;
}

static bool push_val(struct calc_evaluator *ev, int64_t v)
{
    void *buf = ev->vals;
    if (!reserve_one(&buf, &ev->vals_cap, ev->nvals, sizeof *ev->vals))
        return false;
    ev->vals = buf;
    ev->vals[ev->nvals++] = v;
    return true;
}

static bool push_op(struct calc_evaluator *ev, unsigned char op)
{
    void *buf = ev->ops;
    if (!reserve_one(&buf, &ev->ops_cap, ev->nops, sizeof *ev->ops))
        return false;
    ev->ops = buf;
    ev->ops[ev->nops++] = op;
    return true;
}

/*
 * Pops the top operator and applies it to the operand stack. The parser only
 * reduces after a complete operand, so the required operands are present.
 */
static bool reduce(struct calc_evaluator *ev)
{
    unsigned char op = ev->ops[--ev->nops];
    int64_t *top = &ev->vals[ev->nvals - 1];

    if (op == OP_NEG)
        return checked_neg(*top, top);

    int64_t b = *top;
    int64_t *a = top - 1;
    ev->nvals--;
    switch (op) {
    case '+': return checked_add(*a, b, a);
    case '-': return checked_sub(*a, b, a);
    case '*': return checked_mul(*a, b, a);
    case '/': return checked_div(*a, b, a);
    case '%': return checked_rem(*a, b, a);
    default:  return false;
    }
}

/* Reduces every operator above the innermost '(' with precedence >= prec. */
static bool reduce_while(struct calc_evaluator *ev, int prec)
{
    while (ev->nops > 0 && ev->ops[ev->nops - 1] != OP_LPAREN &&
           precedence(ev->ops[ev->nops - 1]) >= prec) {
        if (!reduce(ev))
            return false;
    }
    return true;
}

static bool is_blank(char c)
{
    return c == ' ' || c == '\t';
}

static bool is_digit(char c)
{
    return c >= '0' && c <= '9';
}

enum calc_status calc_eval(struct calc_evaluator *ev, const char *line,
                           size_t len, int64_t *result)
{
    const char *p = line;
    const char *end = line + len;
    bool want_operand = true; /* else an operator or ')' is expected */
    bool any_token = false;

    ev->nvals = 0;
    ev->nops = 0;

    for (;;) {
        while (p < end && is_blank(*p))
            p++;
        if (p == end)
            break;
        any_token = true;
        char c = *p++;

        if (want_operand) {
            if (is_digit(c)) {
                int64_t v = c - '0';
                while (p < end && is_digit(*p)) {
                    int d = *p++ - '0';
                    if (v > (INT64_MAX - d) / 10)
                        return CALC_ERROR;
                    v = v * 10 + d;
                }
                if (!push_val(ev, v))
                    return CALC_NOMEM;
                want_operand = false;
            } else if (c == '(' || c == '-') {
                if (!push_op(ev, c == '(' ? OP_LPAREN : OP_NEG))
                    return CALC_NOMEM;
            } else {
                return CALC_ERROR;
            }
            continue;
        }

        switch (c) {
        case '+': case '-': case '*': case '/': case '%':
            if (!reduce_while(ev, precedence((unsigned char)c)))
                return CALC_ERROR;
            if (!push_op(ev, (unsigned char)c))
                return CALC_NOMEM;
            want_operand = true;
            break;
        case ')':
            if (!reduce_while(ev, 0))
                return CALC_ERROR;
            if (ev->nops == 0)
                return CALC_ERROR; /* unmatched ')' */
            ev->nops--;            /* pop the matching '(' */
            break;
        default:
            return CALC_ERROR;
        }
    }

    if (!any_token)
        return CALC_BLANK;
    if (want_operand)
        return CALC_ERROR; /* missing operand */
    if (!reduce_while(ev, 0))
        return CALC_ERROR;
    if (ev->nops != 0)
        return CALC_ERROR; /* unmatched '(' */

    *result = ev->vals[0];
    return CALC_OK;
}

void calc_evaluator_free(struct calc_evaluator *ev)
{
    free(ev->vals);
    free(ev->ops);
    *ev = (struct calc_evaluator)CALC_EVALUATOR_INIT;
}
