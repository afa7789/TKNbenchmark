/*
 * Expression evaluator using operator-precedence parsing with explicit
 * stacks, so arbitrarily deep nesting cannot overflow the call stack.
 */
#include "calc.h"

#include <stdbool.h>
#include <stdlib.h>

enum { OP_NEG = 'u', OP_LPAREN = '(' };

static bool is_blank(char c) { return c == ' ' || c == '\t'; }

static bool is_digit(char c) { return c >= '0' && c <= '9'; }

static int precedence(unsigned char op)
{
    switch (op) {
    case '+':
    case '-':
        return 1;
    case '*':
    case '/':
    case '%':
        return 2;
    case OP_NEG:
        return 3;
    default:
        return 0; /* '(' never pops */
    }
}

static bool apply_binary(unsigned char op, int64_t a, int64_t b, int64_t *r)
{
    switch (op) {
    case '+':
        return !__builtin_add_overflow(a, b, r);
    case '-':
        return !__builtin_sub_overflow(a, b, r);
    case '*':
        return !__builtin_mul_overflow(a, b, r);
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
    unsigned char *ops;
    size_t nvals;
    size_t nops;
} stacks;

/* Pop one operator and apply it to the value stack. */
static bool reduce(stacks *st)
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

static bool reserve(calc_ctx *ctx, size_t need)
{
    if (need <= ctx->cap)
        return true;
    size_t ncap = ctx->cap ? ctx->cap : 64;
    while (ncap < need) {
        if (ncap > SIZE_MAX / 2)
            return false;
        ncap *= 2;
    }
    if (ncap > SIZE_MAX / sizeof *ctx->vals)
        return false;
    int64_t *v = realloc(ctx->vals, ncap * sizeof *v);
    if (!v)
        return false;
    ctx->vals = v;
    unsigned char *o = realloc(ctx->ops, ncap);
    if (!o)
        return false;
    ctx->ops = o;
    ctx->cap = ncap;
    return true;
}

calc_status calc_eval(calc_ctx *ctx, const char *s, size_t len, int64_t *out)
{
    size_t i = 0;
    while (i < len && is_blank(s[i]))
        i++;
    if (i == len)
        return CALC_BLANK;

    /* Every token is at least one byte, so len bounds both stacks. */
    if (!reserve(ctx, len))
        return CALC_NOMEM;
    stacks st = { .vals = ctx->vals, .ops = ctx->ops };
    bool want_operand = true;

    for (; i < len; i++) {
        char c = s[i];
        if (is_blank(c))
            continue;

        if (want_operand) {
            if (is_digit(c)) {
                int64_t v = 0;
                for (; i < len && is_digit(s[i]); i++) {
                    int d = s[i] - '0';
                    if (v > (INT64_MAX - d) / 10)
                        return CALC_ERROR;
                    v = v * 10 + d;
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
        case '+':
        case '-':
        case '*':
        case '/':
        case '%': {
            int p = precedence((unsigned char)c);
            while (st.nops > 0 && precedence(st.ops[st.nops - 1]) >= p)
                if (!reduce(&st))
                    return CALC_ERROR;
            st.ops[st.nops++] = (unsigned char)c;
            want_operand = true;
            break;
        }
        case ')':
            while (st.nops > 0 && st.ops[st.nops - 1] != OP_LPAREN)
                if (!reduce(&st))
                    return CALC_ERROR;
            if (st.nops == 0)
                return CALC_ERROR;
            st.nops--;
            break;
        default:
            return CALC_ERROR;
        }
    }

    if (want_operand)
        return CALC_ERROR;
    while (st.nops > 0) {
        if (st.ops[st.nops - 1] == OP_LPAREN || !reduce(&st))
            return CALC_ERROR;
    }
    *out = st.vals[0];
    return CALC_OK;
}

void calc_ctx_free(calc_ctx *ctx)
{
    free(ctx->vals);
    free(ctx->ops);
    *ctx = (calc_ctx){0};
}
