/*
 * calc: evaluates one 64-bit signed integer expression per input line.
 *
 * The parser is an iterative operator-precedence (shunting-yard) evaluator
 * with explicit heap-allocated stacks, so arbitrarily deep nesting cannot
 * exhaust the call stack.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- growable buffers ---------- */

typedef struct {
    int64_t *data;
    size_t len, cap;
} ValueStack;

typedef struct {
    char *data;
    size_t len, cap;
} CharBuf;

static void die_oom(void)
{
    fputs("calc: out of memory\n", stderr);
    exit(EXIT_FAILURE);
}

static void *grow(void *ptr, size_t *cap, size_t elem_size)
{
    size_t new_cap = *cap ? *cap * 2 : 64;
    if (new_cap > SIZE_MAX / elem_size)
        die_oom();
    void *p = realloc(ptr, new_cap * elem_size);
    if (!p)
        die_oom();
    *cap = new_cap;
    return p;
}

static void values_push(ValueStack *s, int64_t v)
{
    if (s->len == s->cap)
        s->data = grow(s->data, &s->cap, sizeof *s->data);
    s->data[s->len++] = v;
}

static void chars_push(CharBuf *b, char c)
{
    if (b->len == b->cap)
        b->data = grow(b->data, &b->cap, sizeof *b->data);
    b->data[b->len++] = c;
}

/* ---------- checked arithmetic ---------- */

/* Each returns false on overflow or division by zero; *out is set on success. */

static bool checked_add(int64_t a, int64_t b, int64_t *out)
{
    if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b))
        return false;
    *out = a + b;
    return true;
}

static bool checked_sub(int64_t a, int64_t b, int64_t *out)
{
    if ((b < 0 && a > INT64_MAX + b) || (b > 0 && a < INT64_MIN + b))
        return false;
    *out = a - b;
    return true;
}

static bool checked_mul(int64_t a, int64_t b, int64_t *out)
{
    if (a > 0) {
        if (b > 0 ? a > INT64_MAX / b : b < INT64_MIN / a)
            return false;
    } else if (a < 0) {
        if (b > 0 ? a < INT64_MIN / b : (b != 0 && a < INT64_MAX / b))
            return false;
    }
    *out = a * b;
    return true;
}

static bool checked_div(int64_t a, int64_t b, int64_t *out)
{
    if (b == 0 || (a == INT64_MIN && b == -1))
        return false;
    *out = a / b;
    return true;
}

static bool checked_rem(int64_t a, int64_t b, int64_t *out)
{
    if (b == 0)
        return false;
    *out = (b == -1) ? 0 : a % b; /* INT64_MIN % -1 is UB in C; result is 0 */
    return true;
}

static bool checked_neg(int64_t a, int64_t *out)
{
    if (a == INT64_MIN)
        return false;
    *out = -a;
    return true;
}

/* ---------- evaluator ---------- */

enum { OP_NEG = 'n', OP_LPAREN = '(' };

typedef struct {
    ValueStack values;
    CharBuf ops;
} Evaluator;

static int precedence(char op)
{
    switch (op) {
    case '+': case '-': return 1;
    case '*': case '/': case '%': return 2;
    case OP_NEG: return 3;
    default: return 0; /* '(' never pops */
    }
}

/* Applies the operator `op` to the value stack. */
static bool apply(Evaluator *ev, char op)
{
    ValueStack *vs = &ev->values;
    if (op == OP_NEG) {
        if (vs->len < 1)
            return false;
        return checked_neg(vs->data[vs->len - 1], &vs->data[vs->len - 1]);
    }
    if (vs->len < 2)
        return false;
    int64_t b = vs->data[--vs->len];
    int64_t *a = &vs->data[vs->len - 1];
    switch (op) {
    case '+': return checked_add(*a, b, a);
    case '-': return checked_sub(*a, b, a);
    case '*': return checked_mul(*a, b, a);
    case '/': return checked_div(*a, b, a);
    case '%': return checked_rem(*a, b, a);
    default:  return false;
    }
}

/* Pops and applies operators whose precedence is at least `min_prec`. */
static bool reduce(Evaluator *ev, int min_prec)
{
    CharBuf *ops = &ev->ops;
    while (ops->len > 0) {
        char top = ops->data[ops->len - 1];
        if (top == OP_LPAREN || precedence(top) < min_prec)
            break;
        ops->len--;
        if (!apply(ev, top))
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

/*
 * Evaluates the expression in line[0..len). Returns true and stores the
 * value in *result on success; returns false on any error.
 */
static bool evaluate(Evaluator *ev, const char *line, size_t len, int64_t *result)
{
    ev->values.len = 0;
    ev->ops.len = 0;

    bool expect_operand = true;
    size_t i = 0;

    for (;;) {
        while (i < len && is_blank(line[i]))
            i++;
        if (i == len)
            break;

        char c = line[i];
        if (expect_operand) {
            if (is_digit(c)) {
                int64_t v = 0;
                do {
                    int d = line[i] - '0';
                    if (v > (INT64_MAX - d) / 10)
                        return false;
                    v = v * 10 + d;
                    i++;
                } while (i < len && is_digit(line[i]));
                values_push(&ev->values, v);
                expect_operand = false;
            } else if (c == '-') {
                chars_push(&ev->ops, OP_NEG);
                i++;
            } else if (c == '(') {
                chars_push(&ev->ops, OP_LPAREN);
                i++;
            } else {
                return false;
            }
        } else {
            switch (c) {
            case '+': case '-': case '*': case '/': case '%':
                if (!reduce(ev, precedence(c)))
                    return false;
                chars_push(&ev->ops, c);
                expect_operand = true;
                break;
            case ')':
                if (!reduce(ev, 0))
                    return false;
                if (ev->ops.len == 0)
                    return false; /* unmatched ')' */
                ev->ops.len--;    /* discard '(' */
                break;
            default:
                return false;
            }
            i++;
        }
    }

    if (expect_operand || !reduce(ev, 0) || ev->ops.len != 0 || ev->values.len != 1)
        return false;
    *result = ev->values.data[0];
    return true;
}

/* ---------- I/O ---------- */

/* Reads one line (without '\n') into buf. Returns false at end of input. */
static bool read_line(FILE *in, CharBuf *buf)
{
    buf->len = 0;
    int c;
    while ((c = getc(in)) != EOF) {
        if (c == '\n')
            return true;
        chars_push(buf, (char)c);
    }
    return buf->len > 0;
}

static bool is_blank_line(const char *s, size_t len)
{
    for (size_t i = 0; i < len; i++)
        if (!is_blank(s[i]))
            return false;
    return true;
}

int main(void)
{
    static char out_buf[1 << 16];
    setvbuf(stdout, out_buf, _IOFBF, sizeof out_buf);

    CharBuf line = {0};
    Evaluator ev = {0};

    while (read_line(stdin, &line)) {
        if (is_blank_line(line.data, line.len))
            continue;
        int64_t value;
        if (evaluate(&ev, line.data, line.len, &value))
            printf("%lld\n", (long long)value);
        else
            fputs("error\n", stdout);
    }

    fflush(stdout);
    free(line.data);
    free(ev.values.data);
    free(ev.ops.data);
    return EXIT_SUCCESS;
}
