/*
 * calc: evaluate one signed 64-bit integer expression per line.
 *
 * Parsing uses operator precedence with explicit stacks rather than
 * recursion, so arbitrarily deep nesting cannot overflow the call stack.
 * Any syntax error, division by zero or overflow makes the line "error".
 */
#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>

#include "commands.h"
#include "util.h"

#define OP_NEG 'n' /* unary minus on the operator stack */

typedef struct {
    int64_t *vals;
    char *ops;
    size_t cap; /* capacity of both stacks */
    size_t nvals;
    size_t nops;
} Evaluator;

static bool is_blank(char c)
{
    return c == ' ' || c == '\t';
}

static bool is_digit(char c)
{
    return c >= '0' && c <= '9';
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
    default: /* '(' is never reduced by an operator */
        return 0;
    }
}

/* Compute `a op b` into *out; false on overflow or division by zero. */
static bool apply_binary(char op, int64_t a, int64_t b, int64_t *out)
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
        if (a > 0) {
            if ((b > 0 && a > INT64_MAX / b) || (b < 0 && b < INT64_MIN / a))
                return false;
        } else if (a < 0) {
            if ((b > 0 && a < INT64_MIN / b) || (b < 0 && a < INT64_MAX / b))
                return false;
        }
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
static bool reduce(Evaluator *ev)
{
    char op = ev->ops[--ev->nops];

    if (op == OP_NEG) {
        if (ev->nvals < 1)
            return false;
        int64_t *v = &ev->vals[ev->nvals - 1];
        if (*v == INT64_MIN)
            return false;
        *v = -*v;
        return true;
    }
    if (op == '(' || ev->nvals < 2)
        return false;
    int64_t b = ev->vals[--ev->nvals];
    int64_t *a = &ev->vals[ev->nvals - 1];
    return apply_binary(op, *a, b, a);
}

static void evaluator_reserve(Evaluator *ev, size_t cap)
{
    if (cap <= ev->cap)
        return;
    ev->vals = xrealloc(ev->vals, cap * sizeof *ev->vals);
    ev->ops = xrealloc(ev->ops, cap);
    ev->cap = cap;
}

/* Evaluate the expression in s[0..len); false means "error". */
static bool evaluate(Evaluator *ev, const char *s, size_t len, int64_t *result)
{
    /* Every stack entry consumes at least one input character. */
    evaluator_reserve(ev, len + 1);
    ev->nvals = 0;
    ev->nops = 0;

    bool want_operand = true;
    size_t i = 0;

    while (i < len) {
        char c = s[i];

        if (is_blank(c)) {
            i++;
        } else if (want_operand) {
            if (is_digit(c)) {
                int64_t v = 0;
                for (; i < len && is_digit(s[i]); i++) {
                    int d = s[i] - '0';
                    if (v > (INT64_MAX - d) / 10)
                        return false;
                    v = v * 10 + d;
                }
                ev->vals[ev->nvals++] = v;
                want_operand = false;
            } else if (c == '-') {
                ev->ops[ev->nops++] = OP_NEG;
                i++;
            } else if (c == '(') {
                ev->ops[ev->nops++] = '(';
                i++;
            } else {
                return false;
            }
        } else if (c == '+' || c == '-' || c == '*' || c == '/' || c == '%') {
            int prec = precedence(c);
            while (ev->nops > 0 && precedence(ev->ops[ev->nops - 1]) >= prec) {
                if (!reduce(ev))
                    return false;
            }
            ev->ops[ev->nops++] = c;
            want_operand = true;
            i++;
        } else if (c == ')') {
            while (ev->nops > 0 && ev->ops[ev->nops - 1] != '(') {
                if (!reduce(ev))
                    return false;
            }
            if (ev->nops == 0)
                return false; /* unmatched ')' */
            ev->nops--;
            i++;
        } else {
            return false;
        }
    }

    if (want_operand)
        return false;
    while (ev->nops > 0) {
        if (ev->ops[ev->nops - 1] == '(' || !reduce(ev))
            return false;
    }
    if (ev->nvals != 1)
        return false;
    *result = ev->vals[0];
    return true;
}

static bool is_blank_line(const char *s, size_t len)
{
    for (size_t i = 0; i < len; i++) {
        if (!is_blank(s[i]))
            return false;
    }
    return true;
}

int cmd_calc(FILE *in, FILE *out)
{
    LineReader reader;
    line_reader_init(&reader, in);
    Evaluator ev = { 0 };

    const char *line;
    size_t len;
    while (line_reader_next(&reader, &line, &len)) {
        if (is_blank_line(line, len))
            continue;
        int64_t value;
        if (evaluate(&ev, line, len, &value))
            fprintf(out, "%" PRId64 "\n", value);
        else
            fputs("error\n", out);
    }

    free(ev.vals);
    free(ev.ops);
    line_reader_free(&reader);
    return 0;
}
