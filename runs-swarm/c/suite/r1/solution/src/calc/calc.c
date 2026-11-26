/*
 * `app calc`: 64-bit signed integer expression evaluator.
 *
 * Each input line is one expression:
 *
 *     expr    := term    (('+' | '-') term)*
 *     term    := unary   (('*' | '/' | '%') unary)*
 *     unary   := '-' unary | primary
 *     primary := NUMBER | '(' expr ')'
 *
 * The evaluator is an iterative operator-precedence (shunting-yard) parser
 * with explicit, heap-allocated stacks, so arbitrarily deep nesting such as
 * "((((...))))" or "-----...1" cannot exhaust the C call stack. Both stacks
 * are bounded by the line length and reused across lines.
 */
#include "calc.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------------ */
/* Checked 64-bit arithmetic                                                */
/* ------------------------------------------------------------------------ */

enum calc_status {
    CALC_OK,
    CALC_ERROR,     /* syntax error, division by zero or overflow */
    CALC_NOMEM,
};

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
        if (b > 0 ? a < INT64_MIN / b : (b != 0 && a < INT64_MAX / b))
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
    *r = (b == -1) ? 0 : a % b;
    return true;
}

static bool checked_neg(int64_t a, int64_t *r)
{
    if (a == INT64_MIN)
        return false;
    *r = -a;
    return true;
}

/* ------------------------------------------------------------------------ */
/* Evaluator                                                                */
/* ------------------------------------------------------------------------ */

/* Entries of the operator stack. */
enum op {
    OP_LPAREN,
    OP_ADD,
    OP_SUB,
    OP_MUL,
    OP_DIV,
    OP_MOD,
    OP_NEG,
};

/* Binding strength of binary operators; OP_LPAREN acts as a barrier. */
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

/* Scratch stacks, reused across lines and grown to the longest line seen. */
struct calc_stacks {
    int64_t *vals;
    unsigned char *ops;     /* enum op values */
    size_t cap;
};

static bool stacks_reserve(struct calc_stacks *st, size_t need)
{
    if (need <= st->cap)
        return true;

    size_t cap = st->cap ? st->cap : 64;
    while (cap < need)
        cap *= 2;

    int64_t *vals = realloc(st->vals, cap * sizeof *vals);
    if (vals == NULL)
        return false;
    st->vals = vals;

    unsigned char *ops = realloc(st->ops, cap * sizeof *ops);
    if (ops == NULL)
        return false;
    st->ops = ops;

    st->cap = cap;
    return true;
}

static void stacks_free(struct calc_stacks *st)
{
    free(st->vals);
    free(st->ops);
    *st = (struct calc_stacks){ 0 };
}

/* Pops the top operator and applies it to the value stack. */
static bool apply_top(struct calc_stacks *st, size_t *nvals, size_t *nops)
{
    enum op op = (enum op)st->ops[--*nops];

    if (op == OP_NEG)
        return checked_neg(st->vals[*nvals - 1], &st->vals[*nvals - 1]);

    int64_t b = st->vals[--*nvals];
    int64_t *a = &st->vals[*nvals - 1];

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

/* Applies operators on top of the stack that bind at least as tightly as
 * `prec` (all binary operators are left-associative), stopping at '('. */
static bool reduce(struct calc_stacks *st, size_t *nvals, size_t *nops, int prec)
{
    while (*nops > 0) {
        enum op top = (enum op)st->ops[*nops - 1];
        if (top == OP_LPAREN || precedence(top) < prec)
            break;
        if (!apply_top(st, nvals, nops))
            return false;
    }
    return true;
}

static bool is_blank(char c)
{
    return c == ' ' || c == '\t';
}

/*
 * Evaluates the expression in line[0..len). Returns CALC_OK and stores the
 * value in *out, or CALC_ERROR for any syntax or arithmetic error.
 */
static enum calc_status calc_eval(struct calc_stacks *st, const char *line,
                                  size_t len, int64_t *out)
{
    /* Every stack entry consumes at least one input byte. */
    if (!stacks_reserve(st, len + 1))
        return CALC_NOMEM;

    size_t nvals = 0, nops = 0;
    bool want_operand = true;
    size_t i = 0;

    while (i < len) {
        char c = line[i];

        if (is_blank(c)) {
            i++;
            continue;
        }

        if (want_operand) {
            if (c >= '0' && c <= '9') {
                int64_t v = 0;
                do {
                    int d = line[i] - '0';
                    if (v > (INT64_MAX - d) / 10)
                        return CALC_ERROR;
                    v = v * 10 + d;
                    i++;
                } while (i < len && line[i] >= '0' && line[i] <= '9');

                st->vals[nvals++] = v;
                if (!reduce(st, &nvals, &nops, precedence(OP_NEG)))
                    return CALC_ERROR;
                want_operand = false;
                continue;
            }
            if (c == '-')
                st->ops[nops++] = OP_NEG;
            else if (c == '(')
                st->ops[nops++] = OP_LPAREN;
            else
                return CALC_ERROR;
            i++;
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
            if (!reduce(st, &nvals, &nops, 0))
                return CALC_ERROR;
            if (nops == 0)
                return CALC_ERROR;          /* unmatched ')' */
            nops--;                         /* pop '(' */
            /* The parenthesised value completes a primary for pending '-'. */
            if (!reduce(st, &nvals, &nops, precedence(OP_NEG)))
                return CALC_ERROR;
            i++;
            continue;
        default:
            return CALC_ERROR;
        }

        if (!reduce(st, &nvals, &nops, precedence(op)))
            return CALC_ERROR;
        st->ops[nops++] = (unsigned char)op;
        want_operand = true;
        i++;
    }

    if (want_operand)
        return CALC_ERROR;                  /* empty input or missing operand */
    if (!reduce(st, &nvals, &nops, 0))
        return CALC_ERROR;
    if (nops != 0)
        return CALC_ERROR;                  /* unmatched '(' */

    *out = st->vals[0];
    return CALC_OK;
}

/* ------------------------------------------------------------------------ */
/* Line input                                                               */
/* ------------------------------------------------------------------------ */

struct line_reader {
    FILE *in;
    char *buf;
    size_t cap;
    size_t start;   /* first unconsumed byte */
    size_t end;     /* one past the last buffered byte */
    bool eof;
};

/*
 * Returns the next line (without its '\n') in *line / *len.
 * Returns 1 on success, 0 at end of input, -1 on allocation or read error.
 * The returned pointer is valid until the next call.
 */
static int next_line(struct line_reader *r, const char **line, size_t *len)
{
    size_t scanned = r->start;

    for (;;) {
        char *nl = (scanned < r->end)
                       ? memchr(r->buf + scanned, '\n', r->end - scanned)
                       : NULL;
        if (nl != NULL) {
            *line = r->buf + r->start;
            *len = (size_t)(nl - *line);
            r->start = (size_t)(nl - r->buf) + 1;
            return 1;
        }
        scanned = r->end;

        if (r->eof) {
            if (r->start == r->end)
                return 0;
            *line = r->buf + r->start;      /* final line without '\n' */
            *len = r->end - r->start;
            r->start = r->end;
            return 1;
        }

        /* Discard consumed bytes, then make room for more input. */
        if (r->start > 0) {
            memmove(r->buf, r->buf + r->start, r->end - r->start);
            r->end -= r->start;
            scanned -= r->start;
            r->start = 0;
        }
        if (r->end == r->cap) {
            size_t cap = r->cap ? r->cap * 2 : 1 << 16;
            char *buf = realloc(r->buf, cap);
            if (buf == NULL)
                return -1;
            r->buf = buf;
            r->cap = cap;
        }

        size_t n = fread(r->buf + r->end, 1, r->cap - r->end, r->in);
        r->end += n;
        if (n == 0) {
            if (ferror(r->in))
                return -1;
            r->eof = true;
        }
    }
}

static bool is_blank_line(const char *line, size_t len)
{
    for (size_t i = 0; i < len; i++) {
        if (!is_blank(line[i]))
            return false;
    }
    return true;
}

/* ------------------------------------------------------------------------ */
/* Entry point                                                              */
/* ------------------------------------------------------------------------ */

int calc_main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    struct line_reader reader = { .in = stdin };
    struct calc_stacks stacks = { 0 };
    int status = EXIT_SUCCESS;
    const char *line;
    size_t len;
    int rc;

    while ((rc = next_line(&reader, &line, &len)) > 0) {
        if (is_blank_line(line, len))
            continue;

        int64_t value;
        enum calc_status res = calc_eval(&stacks, line, len, &value);
        if (res == CALC_NOMEM) {
            rc = -1;
            break;
        }
        if (res == CALC_OK)
            printf("%" PRId64 "\n", value);
        else
            fputs("error\n", stdout);
    }

    if (rc < 0) {
        fputs("calc: out of memory or read error\n", stderr);
        status = EXIT_FAILURE;
    }
    if (fflush(stdout) != 0) {
        perror("calc: write error");
        status = EXIT_FAILURE;
    }

    free(reader.buf);
    stacks_free(&stacks);
    return status;
}
