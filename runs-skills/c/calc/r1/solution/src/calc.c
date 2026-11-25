#include "calc.h"

#include <stdbool.h>
#include <stdlib.h>

/*
 * Iterative operator-precedence evaluator (no recursion, so arbitrarily deep
 * nesting cannot overflow the call stack). Operator stack entries are the
 * operator characters themselves; unary minus is stored as 'n'.
 */

enum { OP_NEG = 'n', OP_LPAREN = '(' };

static int precedence(unsigned char op)
{
    switch (op) {
    case '+': case '-': return 1;
    case '*': case '/': case '%': return 2;
    case OP_NEG: return 3;
    default: return 0; /* '(' */
    }
}

static bool apply_binary(unsigned char op, int64_t a, int64_t b, int64_t *r)
{
    switch (op) {
    case '+': return !__builtin_add_overflow(a, b, r);
    case '-': return !__builtin_sub_overflow(a, b, r);
    case '*': return !__builtin_mul_overflow(a, b, r);
    case '/':
        if (b == 0 || (a == INT64_MIN && b == -1))
            return false;
        *r = a / b;
        return true;
    case '%':
        if (b == 0)
            return false;
        *r = (b == -1) ? 0 : a % b;
        return true;
    default:
        return false;
    }
}

typedef struct {
    int64_t *vals;
    size_t nvals;
    unsigned char *ops;
    size_t nops;
} stacks;

/* Pop the top operator and apply it to the value stack. */
static bool reduce_one(stacks *st)
{
    unsigned char op = st->ops[--st->nops];
    if (op == OP_NEG) {
        int64_t *v = &st->vals[st->nvals - 1];
        if (*v == INT64_MIN)
            return false;
        *v = -*v;
        return true;
    }
    int64_t b = st->vals[--st->nvals];
    int64_t *a = &st->vals[st->nvals - 1];
    return apply_binary(op, *a, b, a);
}

/* Reduce while the top operator binds at least as tightly as min_prec. */
static bool reduce_while(stacks *st, int min_prec)
{
    while (st->nops > 0 && st->ops[st->nops - 1] != OP_LPAREN &&
           precedence(st->ops[st->nops - 1]) >= min_prec) {
        if (!reduce_one(st))
            return false;
    }
    return true;
}

static bool reserve(calc_ctx *ctx, size_t need)
{
    if (need <= ctx->cap)
        return true;
    if (need > SIZE_MAX / sizeof *ctx->vals)
        return false;
    int64_t *v = realloc(ctx->vals, need * sizeof *v);
    if (!v)
        return false;
    ctx->vals = v;
    unsigned char *o = realloc(ctx->ops, need);
    if (!o)
        return false;
    ctx->ops = o;
    ctx->cap = need;
    return true;
}

static bool is_blank(char c) { return c == ' ' || c == '\t'; }
static bool is_digit(char c) { return c >= '0' && c <= '9'; }

calc_status calc_eval(calc_ctx *ctx, const char *s, size_t len, int64_t *out)
{
    size_t i = 0;
    while (i < len && is_blank(s[i]))
        i++;
    if (i == len)
        return CALC_EMPTY;

    /* Every token occupies at least one byte, so len bounds both stacks. */
    if (!reserve(ctx, len))
        return CALC_NOMEM;
    stacks st = { ctx->vals, 0, ctx->ops, 0 };
    bool want_operand = true;

    for (; i < len; i++) {
        char c = s[i];
        if (is_blank(c))
            continue;

        if (want_operand) {
            if (is_digit(c)) {
                int64_t v = 0;
                for (; i < len && is_digit(s[i]); i++) {
                    if (__builtin_mul_overflow(v, 10, &v) ||
                        __builtin_add_overflow(v, s[i] - '0', &v))
                        return CALC_ERROR;
                }
                i--;
                st.vals[st.nvals++] = v;
                want_operand = false;
            } else if (c == '-') {
                st.ops[st.nops++] = OP_NEG;
            } else if (c == '(') {
                st.ops[st.nops++] = OP_LPAREN;
            } else {
                return CALC_ERROR;
            }
            continue;
        }

        switch (c) {
        case '+': case '-': case '*': case '/': case '%': {
            unsigned char op = (unsigned char)c;
            if (!reduce_while(&st, precedence(op)))
                return CALC_ERROR;
            st.ops[st.nops++] = op;
            want_operand = true;
            break;
        }
        case ')':
            if (!reduce_while(&st, 0))
                return CALC_ERROR;
            if (st.nops == 0)
                return CALC_ERROR; /* unmatched ')' */
            st.nops--;             /* pop '(' */
            break;
        default:
            return CALC_ERROR;
        }
    }

    if (want_operand)
        return CALC_ERROR; /* missing operand */
    if (!reduce_while(&st, 0))
        return CALC_ERROR;
    if (st.nops != 0)
        return CALC_ERROR; /* unmatched '(' */

    *out = st.vals[0];
    return CALC_OK;
}

void calc_ctx_free(calc_ctx *ctx)
{
    free(ctx->vals);
    free(ctx->ops);
    *ctx = (calc_ctx){0};
}
