/* calc: evaluate one signed 64-bit integer expression per line of stdin.
 *
 * The grammar is evaluated with an explicit operator-precedence (shunting-yard)
 * machine rather than recursive descent, so arbitrarily deep nesting such as
 * "((((...))))" or "------1" cannot exhaust the call stack. */
#include "commands.h"
#include "io.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

enum { OP_NEG = 'n', OP_PAREN = '(' };

typedef struct {
    void *data;
    size_t len;
    size_t cap;
} Stack;

static void stack_reserve(Stack *s, size_t elem)
{
    if (s->len == s->cap) {
        s->cap = s->cap ? s->cap * 2 : 64;
        s->data = xrealloc(s->data, s->cap * elem);
    }
}

typedef struct {
    Stack vals; /* int64_t */
    Stack ops;  /* char: binary operator, OP_NEG or OP_PAREN */
} Machine;

static void push_val(Machine *m, int64_t v)
{
    stack_reserve(&m->vals, sizeof v);
    ((int64_t *)m->vals.data)[m->vals.len++] = v;
}

static void push_op(Machine *m, char op)
{
    stack_reserve(&m->ops, 1);
    ((char *)m->ops.data)[m->ops.len++] = op;
}

static char top_op(const Machine *m)
{
    return m->ops.len ? ((const char *)m->ops.data)[m->ops.len - 1] : '\0';
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
    default:
        return 0; /* OP_PAREN and none: never reduced by an operator */
    }
}

/* Compute a op b exactly; false on overflow or division by zero. */
static bool apply_binary(char op, int64_t a, int64_t b, int64_t *r)
{
    switch (op) {
    case '+':
        if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b))
            return false;
        *r = a + b;
        return true;
    case '-':
        if ((b < 0 && a > INT64_MAX + b) || (b > 0 && a < INT64_MIN + b))
            return false;
        *r = a - b;
        return true;
    case '*':
        if (a == 0 || b == 0) {
            *r = 0;
            return true;
        }
        if (a > 0 ? (b > 0 ? a > INT64_MAX / b : b < INT64_MIN / a)
                  : (b > 0 ? a < INT64_MIN / b : b < INT64_MAX / a))
            return false;
        *r = a * b;
        return true;
    case '/':
        if (b == 0 || (a == INT64_MIN && b == -1))
            return false;
        *r = a / b;
        return true;
    case '%':
        if (b == 0)
            return false;
        *r = b == -1 ? 0 : a % b; /* INT64_MIN % -1 is 0, but UB in C */
        return true;
    default:
        return false;
    }
}

/* Pop and apply the top operator. */
static bool reduce(Machine *m)
{
    char op = ((char *)m->ops.data)[--m->ops.len];
    int64_t *v = m->vals.data;
    if (op == OP_NEG) {
        int64_t *x = &v[m->vals.len - 1];
        if (*x == INT64_MIN)
            return false;
        *x = -*x;
        return true;
    }
    int64_t b = v[--m->vals.len];
    int64_t *a = &v[m->vals.len - 1];
    return apply_binary(op, *a, b, a);
}

/* Apply stacked operators that bind at least as tightly as prec. */
static bool reduce_while(Machine *m, int prec)
{
    while (m->ops.len && precedence(top_op(m)) >= prec && top_op(m) != OP_PAREN) {
        if (!reduce(m))
            return false;
    }
    return true;
}

static inline bool is_blank(char c)
{
    return c == ' ' || c == '\t';
}

static inline bool is_digit(char c)
{
    return c >= '0' && c <= '9';
}

/* Evaluate the expression in [p, end). */
static bool evaluate(Machine *m, const char *p, const char *end, int64_t *result)
{
    m->vals.len = 0;
    m->ops.len = 0;
    bool want_operand = true;

    for (;;) {
        while (p < end && is_blank(*p))
            p++;
        if (p == end)
            break;
        char c = *p;

        if (want_operand) {
            if (is_digit(c)) {
                int64_t v = 0;
                for (; p < end && is_digit(*p); p++) {
                    int d = *p - '0';
                    if (v > (INT64_MAX - d) / 10)
                        return false; /* literal out of range */
                    v = v * 10 + d;
                }
                push_val(m, v);
                want_operand = false;
                continue;
            }
            if (c == '-')
                push_op(m, OP_NEG);
            else if (c == '(')
                push_op(m, OP_PAREN);
            else
                return false;
            p++;
            continue;
        }

        switch (c) {
        case '+':
        case '-':
        case '*':
        case '/':
        case '%':
            if (!reduce_while(m, precedence(c)))
                return false;
            push_op(m, c);
            want_operand = true;
            break;
        case ')':
            if (!reduce_while(m, 1))
                return false;
            if (top_op(m) != OP_PAREN)
                return false; /* unmatched ')' */
            m->ops.len--;
            break;
        default:
            return false;
        }
        p++;
    }

    if (want_operand)
        return false; /* empty input or dangling operator */
    if (!reduce_while(m, 1) || m->ops.len)
        return false; /* arithmetic error or unmatched '(' */
    *result = ((int64_t *)m->vals.data)[0];
    return true;
}

int cmd_calc(void)
{
    Input in = input_read_all(stdin);
    const char *p = in.data;
    const char *end = in.data + in.len;
    Machine m = { 0 };
    Output out;
    out_init(&out, stdout);

    while (p < end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        const char *e = nl ? nl : end;

        const char *q = p;
        while (q < e && is_blank(*q))
            q++;
        if (q < e) {
            int64_t v;
            if (evaluate(&m, q, e, &v))
                out_i64(&out, v);
            else
                out_write(&out, "error", 5);
            out_char(&out, '\n');
        }
        p = nl ? nl + 1 : end;
    }

    out_finish(&out);
    free(m.vals.data);
    free(m.ops.data);
    input_free(&in);
    return EXIT_SUCCESS;
}
