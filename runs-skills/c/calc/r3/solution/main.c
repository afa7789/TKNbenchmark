/*
 * calc: 64-bit signed integer expression evaluator.
 *
 * Reads one expression per line from stdin and prints its value or "error".
 * Parsing uses an explicit-stack operator-precedence algorithm, so arbitrarily
 * deep nesting cannot exhaust the C call stack.
 */
#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* ---------- growable stacks ---------- */

typedef struct {
    int64_t *data;
    size_t len, cap;
} ValStack;

typedef struct {
    char *data;
    size_t len, cap;
} OpStack;

static bool grow(void **data, size_t *cap, size_t elem)
{
    size_t ncap = *cap ? *cap * 2 : 64;
    if (ncap > SIZE_MAX / elem) return false;
    void *p = realloc(*data, ncap * elem);
    if (!p) return false;
    *data = p;
    *cap = ncap;
    return true;
}

static bool val_push(ValStack *s, int64_t v)
{
    if (s->len == s->cap && !grow((void **)&s->data, &s->cap, sizeof *s->data)) return false;
    s->data[s->len++] = v;
    return true;
}

static bool op_push(OpStack *s, char op)
{
    if (s->len == s->cap && !grow((void **)&s->data, &s->cap, sizeof *s->data)) return false;
    s->data[s->len++] = op;
    return true;
}

/* ---------- evaluation ---------- */

enum { OP_NEG = 'n', OP_LPAREN = '(' };

static int precedence(char op)
{
    switch (op) {
    case '+': case '-': return 1;
    case '*': case '/': case '%': return 2;
    case OP_NEG: return 3;
    default: return 0; /* '(' */
    }
}

/* Applies a binary operator; returns false on overflow or division by zero. */
static bool apply_binary(char op, int64_t a, int64_t b, int64_t *out)
{
    switch (op) {
    case '+': return !__builtin_add_overflow(a, b, out);
    case '-': return !__builtin_sub_overflow(a, b, out);
    case '*': return !__builtin_mul_overflow(a, b, out);
    case '/':
        if (b == 0 || (a == INT64_MIN && b == -1)) return false;
        *out = a / b;
        return true;
    case '%':
        if (b == 0) return false;
        *out = (b == -1) ? 0 : a % b;
        return true;
    default:
        return false;
    }
}

/* Pops the top operator and applies it to the value stack. */
static bool reduce(ValStack *vals, OpStack *ops)
{
    char op = ops->data[--ops->len];
    if (op == OP_NEG) {
        if (vals->len < 1) return false;
        int64_t *v = &vals->data[vals->len - 1];
        if (*v == INT64_MIN) return false;
        *v = -*v;
        return true;
    }
    if (vals->len < 2) return false;
    int64_t b = vals->data[--vals->len];
    int64_t *a = &vals->data[vals->len - 1];
    return apply_binary(op, *a, b, a);
}

typedef enum { EVAL_OK, EVAL_ERROR, EVAL_EMPTY, EVAL_NOMEM } EvalStatus;

static bool is_blank(char c) { return c == ' ' || c == '\t'; }
static bool is_digit(char c) { return c >= '0' && c <= '9'; }

/* Evaluates the expression in line[0..len). */
static EvalStatus evaluate(const char *line, size_t len, ValStack *vals, OpStack *ops,
                           int64_t *result)
{
    vals->len = 0;
    ops->len = 0;
    bool expect_operand = true;
    bool any_token = false;
    size_t i = 0;

    while (i < len) {
        char c = line[i];
        if (is_blank(c)) {
            i++;
            continue;
        }
        any_token = true;

        if (expect_operand) {
            if (is_digit(c)) {
                int64_t v = 0;
                bool overflow = false;
                for (; i < len && is_digit(line[i]); i++) {
                    int d = line[i] - '0';
                    if (v > (INT64_MAX - d) / 10) overflow = true;
                    else v = v * 10 + d;
                }
                if (overflow) return EVAL_ERROR;
                if (!val_push(vals, v)) return EVAL_NOMEM;
                expect_operand = false;
                continue;
            }
            if (c == '-' || c == '(') {
                if (!op_push(ops, c == '-' ? (char)OP_NEG : (char)OP_LPAREN)) return EVAL_NOMEM;
                i++;
                continue;
            }
            return EVAL_ERROR;
        }

        if (c == ')') {
            while (ops->len > 0 && ops->data[ops->len - 1] != OP_LPAREN)
                if (!reduce(vals, ops)) return EVAL_ERROR;
            if (ops->len == 0) return EVAL_ERROR;
            ops->len--; /* discard '(' */
            i++;
            continue;
        }
        if (c == '+' || c == '-' || c == '*' || c == '/' || c == '%') {
            int prec = precedence(c);
            while (ops->len > 0 && precedence(ops->data[ops->len - 1]) >= prec)
                if (!reduce(vals, ops)) return EVAL_ERROR;
            if (!op_push(ops, c)) return EVAL_NOMEM;
            expect_operand = true;
            i++;
            continue;
        }
        return EVAL_ERROR;
    }

    if (!any_token) return EVAL_EMPTY;
    if (expect_operand) return EVAL_ERROR;
    while (ops->len > 0) {
        if (ops->data[ops->len - 1] == OP_LPAREN) return EVAL_ERROR;
        if (!reduce(vals, ops)) return EVAL_ERROR;
    }
    if (vals->len != 1) return EVAL_ERROR;
    *result = vals->data[0];
    return EVAL_OK;
}

/* ---------- input ---------- */

/* Reads all of stdin into a heap buffer. Returns NULL on failure. */
static char *read_all(FILE *in, size_t *out_len)
{
    size_t len = 0, cap = 0;
    char *buf = NULL;
    for (;;) {
        if (len == cap && !grow((void **)&buf, &cap, 1)) {
            free(buf);
            return NULL;
        }
        size_t n = fread(buf + len, 1, cap - len, in);
        len += n;
        if (n == 0) {
            if (ferror(in)) {
                free(buf);
                return NULL;
            }
            break;
        }
    }
    *out_len = len;
    return buf;
}

int main(void)
{
    size_t len = 0;
    char *input = read_all(stdin, &len);
    if (!input) {
        fputs("calc: failed to read input\n", stderr);
        return EXIT_FAILURE;
    }

    ValStack vals = {0};
    OpStack ops = {0};
    int status = EXIT_SUCCESS;

    size_t start = 0;
    while (start < len) {
        size_t end = start;
        while (end < len && input[end] != '\n') end++;

        int64_t value = 0;
        EvalStatus st = evaluate(input + start, end - start, &vals, &ops, &value);
        if (st == EVAL_OK) {
            printf("%" PRId64 "\n", value);
        } else if (st == EVAL_ERROR) {
            fputs("error\n", stdout);
        } else if (st == EVAL_NOMEM) {
            fputs("calc: out of memory\n", stderr);
            status = EXIT_FAILURE;
            break;
        }
        start = end + 1;
    }

    free(vals.data);
    free(ops.data);
    free(input);
    if (fflush(stdout) != 0) status = EXIT_FAILURE;
    return status;
}
