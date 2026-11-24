/*
 * calc: evaluate one 64-bit signed integer expression per input line.
 *
 * Parsing uses an iterative operator-precedence (shunting-yard) evaluator
 * with explicit stacks, so arbitrarily deep nesting cannot exhaust the
 * call stack.
 */
#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Operator codes held on the operator stack. */
enum {
    OP_LPAREN = '(',
    OP_NEG = 'n',
    OP_ADD = '+',
    OP_SUB = '-',
    OP_MUL = '*',
    OP_DIV = '/',
    OP_MOD = '%',
};

typedef struct {
    int64_t *vals;
    char *ops;
    size_t cap;   /* capacity of both stacks */
    size_t nvals;
    size_t nops;
} Evaluator;

static void die_oom(void)
{
    fputs("calc: out of memory\n", stderr);
    exit(EXIT_FAILURE);
}

/* Ensure both stacks can hold at least `need` entries. */
static void evaluator_reserve(Evaluator *ev, size_t need)
{
    if (need <= ev->cap)
        return;
    size_t cap = ev->cap ? ev->cap : 64;
    while (cap < need)
        cap *= 2;
    int64_t *vals = realloc(ev->vals, cap * sizeof *vals);
    if (!vals)
        die_oom();
    ev->vals = vals;
    char *ops = realloc(ev->ops, cap);
    if (!ops)
        die_oom();
    ev->ops = ops;
    ev->cap = cap;
}

static void evaluator_free(Evaluator *ev)
{
    free(ev->vals);
    free(ev->ops);
}

static int precedence(char op)
{
    switch (op) {
    case OP_NEG:
        return 3;
    case OP_MUL:
    case OP_DIV:
    case OP_MOD:
        return 2;
    case OP_ADD:
    case OP_SUB:
        return 1;
    default:
        return 0; /* '(' never reduces by precedence */
    }
}

static bool is_blank(char c)
{
    return c == ' ' || c == '\t';
}

/* Apply a binary operator; returns false on overflow or division by zero. */
static bool apply_binary(char op, int64_t a, int64_t b, int64_t *out)
{
    switch (op) {
    case OP_ADD:
        return !__builtin_add_overflow(a, b, out);
    case OP_SUB:
        return !__builtin_sub_overflow(a, b, out);
    case OP_MUL:
        return !__builtin_mul_overflow(a, b, out);
    case OP_DIV:
        if (b == 0 || (a == INT64_MIN && b == -1))
            return false;
        *out = a / b;
        return true;
    case OP_MOD:
        if (b == 0)
            return false;
        *out = (b == -1) ? 0 : a % b;
        return true;
    default:
        return false;
    }
}

/* Pop the top operator and apply it to the value stack. */
static bool reduce_one(Evaluator *ev)
{
    char op = ev->ops[--ev->nops];
    if (op == OP_NEG) {
        int64_t *v = &ev->vals[ev->nvals - 1];
        if (*v == INT64_MIN)
            return false;
        *v = -*v;
        return true;
    }
    int64_t b = ev->vals[--ev->nvals];
    int64_t *a = &ev->vals[ev->nvals - 1];
    return apply_binary(op, *a, b, a);
}

/* Reduce while the top operator binds at least as tightly as `prec`. */
static bool reduce_while(Evaluator *ev, int prec)
{
    while (ev->nops > 0 && ev->ops[ev->nops - 1] != OP_LPAREN &&
           precedence(ev->ops[ev->nops - 1]) >= prec) {
        if (!reduce_one(ev))
            return false;
    }
    return true;
}

/*
 * Evaluate the expression in line[0..len). Returns true and stores the
 * result on success; false on any syntax or arithmetic error.
 */
static bool evaluate(Evaluator *ev, const char *line, size_t len, int64_t *result)
{
    /* Every token occupies at least one byte, bounding both stacks. */
    evaluator_reserve(ev, len + 1);
    ev->nvals = 0;
    ev->nops = 0;

    bool want_operand = true;
    size_t i = 0;

    for (;;) {
        while (i < len && is_blank(line[i]))
            i++;

        if (want_operand) {
            if (i == len)
                return false;
            char c = line[i];
            if (c == '-') {
                ev->ops[ev->nops++] = OP_NEG;
                i++;
            } else if (c == '(') {
                ev->ops[ev->nops++] = OP_LPAREN;
                i++;
            } else if (c >= '0' && c <= '9') {
                uint64_t v = 0;
                bool overflow = false;
                do {
                    unsigned d = (unsigned)(line[i] - '0');
                    if (v > ((uint64_t)INT64_MAX - d) / 10)
                        overflow = true;
                    else
                        v = v * 10 + d;
                    i++;
                } while (i < len && line[i] >= '0' && line[i] <= '9');
                if (overflow)
                    return false;
                ev->vals[ev->nvals++] = (int64_t)v;
                want_operand = false;
            } else {
                return false;
            }
            continue;
        }

        if (i == len)
            break;

        char c = line[i++];
        switch (c) {
        case ')':
            if (!reduce_while(ev, 0))
                return false;
            if (ev->nops == 0)
                return false; /* unmatched ')' */
            ev->nops--;       /* discard '(' */
            break;
        case OP_ADD:
        case OP_SUB:
        case OP_MUL:
        case OP_DIV:
        case OP_MOD:
            if (!reduce_while(ev, precedence(c)))
                return false;
            ev->ops[ev->nops++] = c;
            want_operand = true;
            break;
        default:
            return false;
        }
    }

    if (!reduce_while(ev, 0))
        return false;
    if (ev->nops != 0)
        return false; /* unmatched '(' */
    *result = ev->vals[0];
    return true;
}

static bool is_blank_line(const char *line, size_t len)
{
    for (size_t i = 0; i < len; i++)
        if (!is_blank(line[i]))
            return false;
    return true;
}

/* Read all of `f` into a heap buffer. */
static char *read_all(FILE *f, size_t *out_len)
{
    size_t cap = 1 << 16, len = 0;
    char *buf = malloc(cap);
    if (!buf)
        die_oom();
    for (;;) {
        if (len == cap) {
            cap *= 2;
            char *nb = realloc(buf, cap);
            if (!nb)
                die_oom();
            buf = nb;
        }
        size_t n = fread(buf + len, 1, cap - len, f);
        len += n;
        if (n == 0)
            break;
    }
    *out_len = len;
    return buf;
}

int main(void)
{
    static char outbuf[1 << 16];
    setvbuf(stdout, outbuf, _IOFBF, sizeof outbuf);

    size_t len;
    char *input = read_all(stdin, &len);
    Evaluator ev = {0};

    size_t pos = 0;
    while (pos < len) {
        const char *line = input + pos;
        const char *nl = memchr(line, '\n', len - pos);
        size_t line_len = nl ? (size_t)(nl - line) : len - pos;
        pos += line_len + (nl ? 1 : 0);

        if (is_blank_line(line, line_len))
            continue;

        int64_t value;
        if (evaluate(&ev, line, line_len, &value))
            printf("%" PRId64 "\n", value);
        else
            fputs("error\n", stdout);
    }

    evaluator_free(&ev);
    free(input);
    fflush(stdout);
    return 0;
}
