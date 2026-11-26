/*
 * calc: evaluate one 64-bit signed integer expression per line.
 *
 * The evaluator is an operator-precedence (shunting-yard) parser with
 * explicit stacks, so deeply nested input cannot overflow the C stack.
 * Any syntax error, division by zero or overflow makes the line "error".
 */
#include "commands.h"
#include "util.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define OP_NEG 'n'

typedef struct {
    int64_t *vals;
    size_t nvals, vals_cap;
    char *ops;
    size_t nops, ops_cap;
} Stacks;

static void push_val(Stacks *st, int64_t v)
{
    if (st->nvals == st->vals_cap) {
        st->vals_cap = st->vals_cap ? st->vals_cap * 2 : 64;
        st->vals = xrealloc(st->vals, sizeof *st->vals * st->vals_cap);
    }
    st->vals[st->nvals++] = v;
}

static void push_op(Stacks *st, char op)
{
    if (st->nops == st->ops_cap) {
        st->ops_cap = st->ops_cap ? st->ops_cap * 2 : 64;
        st->ops = xrealloc(st->ops, st->ops_cap);
    }
    st->ops[st->nops++] = op;
}

static int precedence(char op)
{
    switch (op) {
    case OP_NEG:
        return 3;
    case '*':
    case '/':
    case '%':
        return 2;
    case '+':
    case '-':
        return 1;
    default: /* '(' */
        return 0;
    }
}

/* Compute a op b; returns false on overflow or division by zero. */
static bool binary(char op, int64_t a, int64_t b, int64_t *out)
{
    switch (op) {
    case '+':
        if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b))
            return false;
        *out = a + b;
        return true;
    case '-':
        if ((b < 0 && a > INT64_MAX + b) || (b > 0 && a < INT64_MIN + b))
            return false;
        *out = a - b;
        return true;
    case '*':
        if (a > 0 ? (b > 0 ? a > INT64_MAX / b : b < INT64_MIN / a)
                  : (b > 0 ? a < INT64_MIN / b : (a != 0 && b < INT64_MAX / a)))
            return false;
        *out = a * b;
        return true;
    case '/':
        if (b == 0 || (a == INT64_MIN && b == -1))
            return false;
        *out = a / b;
        return true;
    case '%':
        if (b == 0)
            return false;
        *out = b == -1 ? 0 : a % b;
        return true;
    default:
        return false;
    }
}

/* Pop the top operator and apply it to the value stack. */
static bool reduce(Stacks *st)
{
    char op = st->ops[--st->nops];
    if (op == OP_NEG) {
        int64_t *v = &st->vals[st->nvals - 1];
        if (*v == INT64_MIN)
            return false;
        *v = -*v;
        return true;
    }
    int64_t b = st->vals[--st->nvals];
    int64_t *a = &st->vals[st->nvals - 1];
    return binary(op, *a, b, a);
}

static bool is_blank(char c)
{
    return c == ' ' || c == '\t';
}

static bool is_digit(char c)
{
    return c >= '0' && c <= '9';
}

static bool evaluate(Stacks *st, const char *s, size_t len, int64_t *result)
{
    st->nvals = st->nops = 0;
    bool want_operand = true;
    size_t i = 0;

    while (i < len) {
        char c = s[i];
        if (is_blank(c)) {
            i++;
            continue;
        }
        if (want_operand) {
            if (is_digit(c)) {
                int64_t v = 0;
                for (; i < len && is_digit(s[i]); i++) {
                    int d = s[i] - '0';
                    if (v > (INT64_MAX - d) / 10)
                        return false;
                    v = v * 10 + d;
                }
                push_val(st, v);
                want_operand = false;
                continue;
            }
            if (c == '-')
                push_op(st, OP_NEG);
            else if (c == '(')
                push_op(st, '(');
            else
                return false;
        } else {
            if (c == '+' || c == '-' || c == '*' || c == '/' || c == '%') {
                int p = precedence(c);
                while (st->nops > 0 && precedence(st->ops[st->nops - 1]) >= p)
                    if (!reduce(st))
                        return false;
                push_op(st, c);
                want_operand = true;
            } else if (c == ')') {
                while (st->nops > 0 && st->ops[st->nops - 1] != '(')
                    if (!reduce(st))
                        return false;
                if (st->nops == 0)
                    return false;
                st->nops--;
            } else {
                return false;
            }
        }
        i++;
    }

    if (want_operand)
        return false;
    while (st->nops > 0) {
        if (st->ops[st->nops - 1] == '(' || !reduce(st))
            return false;
    }
    *result = st->vals[0];
    return true;
}

static bool is_blank_line(const char *s, size_t len)
{
    for (size_t i = 0; i < len; i++)
        if (!is_blank(s[i]))
            return false;
    return true;
}

int cmd_calc(void)
{
    LineReader lr;
    line_reader_init(&lr, stdin);
    Stacks st = {0};

    const char *s;
    size_t len;
    while (line_reader_next(&lr, &s, &len)) {
        if (is_blank_line(s, len))
            continue;
        int64_t v;
        if (evaluate(&st, s, len, &v))
            printf("%" PRId64 "\n", v);
        else
            fputs("error\n", stdout);
    }

    free(st.vals);
    free(st.ops);
    line_reader_free(&lr);
    return 0;
}
