/*
 * `app calc`: evaluate one 64-bit signed integer expression per input line.
 *
 * The parser is an operator-precedence (shunting-yard) evaluator driven by
 * explicit, growable stacks rather than recursion, so arbitrarily deep
 * nesting such as "((((...))))" or "-----1" cannot exhaust the C stack.
 * Values are reduced eagerly as operators are popped, and every arithmetic
 * step is checked for overflow without invoking undefined behaviour.
 */
#include "calc.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum op {
    OP_LPAREN,
    OP_ADD,
    OP_SUB,
    OP_MUL,
    OP_DIV,
    OP_MOD,
    OP_NEG,
};

enum status {
    ST_OK,      /* *out holds the value */
    ST_BLANK,   /* line is empty or whitespace only: print nothing */
    ST_ERROR,   /* syntax, division by zero, or overflow */
    ST_NOMEM,   /* allocation failure */
};

struct evaluator {
    int64_t *vals;
    size_t nvals, capvals;
    unsigned char *ops;
    size_t nops, capops;
};

static int precedence(enum op op)
{
    switch (op) {
    case OP_ADD:
    case OP_SUB:
        return 1;
    case OP_MUL:
    case OP_DIV:
    case OP_MOD:
        return 2;
    case OP_NEG:
        return 3;
    case OP_LPAREN:
        break;
    }
    return 0;
}

/* Ensure room for one more element in a stack; returns false on ENOMEM. */
static bool reserve(void **base, size_t *cap, size_t len, size_t elem)
{
    if (len < *cap)
        return true;
    size_t ncap = *cap ? *cap * 2 : 64;
    if (ncap > SIZE_MAX / elem)
        return false;
    void *p = realloc(*base, ncap * elem);
    if (!p)
        return false;
    *base = p;
    *cap = ncap;
    return true;
}

static bool push_val(struct evaluator *ev, int64_t v)
{
    void *base = ev->vals;
    if (!reserve(&base, &ev->capvals, ev->nvals, sizeof *ev->vals))
        return false;
    ev->vals = base;
    ev->vals[ev->nvals++] = v;
    return true;
}

static bool push_op(struct evaluator *ev, enum op op)
{
    void *base = ev->ops;
    if (!reserve(&base, &ev->capops, ev->nops, sizeof *ev->ops))
        return false;
    ev->ops = base;
    ev->ops[ev->nops++] = (unsigned char)op;
    return true;
}

/* Checked arithmetic: each returns false if the exact result is out of range. */
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
        if (b > 0 ? a < INT64_MIN / b : (b < 0 && a < INT64_MAX / b))
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

static bool checked_mod(int64_t a, int64_t b, int64_t *r)
{
    if (b == 0)
        return false;
    /* INT64_MIN % -1 is mathematically 0 but undefined behaviour in C. */
    *r = b == -1 ? 0 : a % b;
    return true;
}

/* Pop the top operator (never a parenthesis) and reduce its operands. */
static bool apply_top(struct evaluator *ev)
{
    enum op op = (enum op)ev->ops[--ev->nops];

    if (op == OP_NEG) {
        int64_t *a = &ev->vals[ev->nvals - 1];
        if (*a == INT64_MIN)
            return false;
        *a = -*a;
        return true;
    }

    int64_t b = ev->vals[--ev->nvals];
    int64_t *a = &ev->vals[ev->nvals - 1];
    switch (op) {
    case OP_ADD: return checked_add(*a, b, a);
    case OP_SUB: return checked_sub(*a, b, a);
    case OP_MUL: return checked_mul(*a, b, a);
    case OP_DIV: return checked_div(*a, b, a);
    case OP_MOD: return checked_mod(*a, b, a);
    case OP_NEG:
    case OP_LPAREN:
        break;
    }
    return false;
}

static bool is_blank(char c)
{
    return c == ' ' || c == '\t';
}

static bool is_digit(char c)
{
    return c >= '0' && c <= '9';
}

static enum status evaluate(struct evaluator *ev, const char *s, size_t len,
                            int64_t *out)
{
    size_t i = 0;
    bool expect_operand = true;
    bool any_token = false;

    ev->nvals = 0;
    ev->nops = 0;

    for (;;) {
        while (i < len && is_blank(s[i]))
            i++;
        if (i == len)
            break;
        any_token = true;
        char c = s[i++];

        if (expect_operand) {
            if (is_digit(c)) {
                int64_t v = c - '0';
                while (i < len && is_digit(s[i])) {
                    int d = s[i++] - '0';
                    if (v > (INT64_MAX - d) / 10)
                        return ST_ERROR;
                    v = v * 10 + d;
                }
                if (!push_val(ev, v))
                    return ST_NOMEM;
                expect_operand = false;
            } else if (c == '-') {
                if (!push_op(ev, OP_NEG))
                    return ST_NOMEM;
            } else if (c == '(') {
                if (!push_op(ev, OP_LPAREN))
                    return ST_NOMEM;
            } else {
                return ST_ERROR;
            }
            continue;
        }

        enum op op;
        switch (c) {
        case '+': op = OP_ADD; break;
        case '-': op = OP_SUB; break;
        case '*': op = OP_MUL; break;
        case '/': op = OP_DIV; break;
        case '%': op = OP_MOD; break;
        case ')':
            while (ev->nops > 0 && ev->ops[ev->nops - 1] != OP_LPAREN) {
                if (!apply_top(ev))
                    return ST_ERROR;
            }
            if (ev->nops == 0)
                return ST_ERROR;    /* unmatched ')' */
            ev->nops--;
            continue;
        default:
            return ST_ERROR;
        }

        /* All binary operators are left-associative. */
        int prec = precedence(op);
        while (ev->nops > 0 && ev->ops[ev->nops - 1] != OP_LPAREN &&
               precedence((enum op)ev->ops[ev->nops - 1]) >= prec) {
            if (!apply_top(ev))
                return ST_ERROR;
        }
        if (!push_op(ev, op))
            return ST_NOMEM;
        expect_operand = true;
    }

    if (!any_token)
        return ST_BLANK;
    if (expect_operand)
        return ST_ERROR;            /* missing operand */

    while (ev->nops > 0) {
        if (ev->ops[ev->nops - 1] == OP_LPAREN)
            return ST_ERROR;        /* unmatched '(' */
        if (!apply_top(ev))
            return ST_ERROR;
    }
    *out = ev->vals[0];
    return ST_OK;
}

/* Evaluate one line and print its result; returns false on ENOMEM. */
static bool process_line(struct evaluator *ev, const char *s, size_t len)
{
    int64_t value;

    switch (evaluate(ev, s, len, &value)) {
    case ST_OK:
        printf("%" PRId64 "\n", value);
        break;
    case ST_ERROR:
        fputs("error\n", stdout);
        break;
    case ST_BLANK:
        break;
    case ST_NOMEM:
        return false;
    }
    return true;
}

/* Append bytes to the pending partial line; returns false on ENOMEM. */
static bool append(char **buf, size_t *len, size_t *cap, const char *s, size_t n)
{
    if (n > *cap - *len) {
        size_t ncap = *cap ? *cap : 4096;
        while (ncap - *len < n) {
            if (ncap > SIZE_MAX / 2)
                return false;
            ncap *= 2;
        }
        char *p = realloc(*buf, ncap);
        if (!p)
            return false;
        *buf = p;
        *cap = ncap;
    }
    memcpy(*buf + *len, s, n);
    *len += n;
    return true;
}

int calc_main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    static char chunk[1 << 16];
    struct evaluator ev = { 0 };
    char *line = NULL;          /* holds a line split across chunks */
    size_t line_len = 0, line_cap = 0;
    bool ok = true;
    size_t n;

    while (ok && (n = fread(chunk, 1, sizeof chunk, stdin)) > 0) {
        const char *p = chunk, *end = chunk + n;
        const char *nl;

        while (ok && (nl = memchr(p, '\n', (size_t)(end - p))) != NULL) {
            size_t seg = (size_t)(nl - p);
            if (line_len > 0) {
                ok = append(&line, &line_len, &line_cap, p, seg) &&
                     process_line(&ev, line, line_len);
                line_len = 0;
            } else {
                ok = process_line(&ev, p, seg);
            }
            p = nl + 1;
        }
        if (ok && p < end)
            ok = append(&line, &line_len, &line_cap, p, (size_t)(end - p));
    }

    /* A final line without a trailing newline is still an expression. */
    if (ok && line_len > 0)
        ok = process_line(&ev, line, line_len);

    free(line);
    free(ev.vals);
    free(ev.ops);

    if (!ok) {
        fputs("calc: out of memory\n", stderr);
        return EXIT_FAILURE;
    }
    if (ferror(stdin)) {
        perror("calc: read error");
        return EXIT_FAILURE;
    }
    if (fflush(stdout) != 0) {
        perror("calc: write error");
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
