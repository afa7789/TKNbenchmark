/*
 * calc — a 64-bit signed integer expression evaluator.
 *
 * Reads one expression per line from standard input and prints its value or
 * "error". Parsing uses an explicit-stack operator-precedence algorithm, so
 * arbitrarily deep nesting cannot exhaust the call stack.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- checked 64-bit arithmetic ---------- */

static bool add_ok(int64_t a, int64_t b, int64_t *r)
{
    if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b))
        return false;
    *r = a + b;
    return true;
}

static bool sub_ok(int64_t a, int64_t b, int64_t *r)
{
    if ((b < 0 && a > INT64_MAX + b) || (b > 0 && a < INT64_MIN + b))
        return false;
    *r = a - b;
    return true;
}

static bool mul_ok(int64_t a, int64_t b, int64_t *r)
{
    if (a == 0 || b == 0) {
        *r = 0;
        return true;
    }
    if (a > 0) {
        if (b > 0 ? a > INT64_MAX / b : b < INT64_MIN / a)
            return false;
    } else {
        if (b > 0 ? a < INT64_MIN / b : b < INT64_MAX / a)
            return false;
    }
    *r = a * b;
    return true;
}

static bool div_ok(int64_t a, int64_t b, int64_t *r)
{
    if (b == 0 || (a == INT64_MIN && b == -1))
        return false;
    *r = a / b;
    return true;
}

static bool mod_ok(int64_t a, int64_t b, int64_t *r)
{
    if (b == 0)
        return false;
    *r = (b == -1) ? 0 : a % b; /* INT64_MIN % -1 is UB in C; result is 0 */
    return true;
}

static bool neg_ok(int64_t a, int64_t *r)
{
    if (a == INT64_MIN)
        return false;
    *r = -a;
    return true;
}

/* ---------- evaluator ---------- */

enum op {
    OP_LPAREN,
    OP_ADD,
    OP_SUB,
    OP_MUL,
    OP_DIV,
    OP_MOD,
    OP_NEG,
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

/* Working storage reused across lines; each stack holds at most one entry
 * per input character. */
struct evaluator {
    int64_t *vals;
    unsigned char *ops;
    size_t cap;
};

static bool evaluator_reserve(struct evaluator *ev, size_t n)
{
    if (n <= ev->cap)
        return true;
    size_t cap = ev->cap ? ev->cap : 256;
    while (cap < n)
        cap *= 2;
    int64_t *vals = realloc(ev->vals, cap * sizeof *vals);
    if (!vals)
        return false;
    ev->vals = vals;
    unsigned char *ops = realloc(ev->ops, cap);
    if (!ops)
        return false;
    ev->ops = ops;
    ev->cap = cap;
    return true;
}

static void evaluator_free(struct evaluator *ev)
{
    free(ev->vals);
    free(ev->ops);
    *ev = (struct evaluator){0};
}

/* Pops the top operator and applies it to the value stack. */
static bool apply_top(int64_t *vals, size_t *nvals, unsigned char *ops, size_t *nops)
{
    enum op op = (enum op)ops[--*nops];
    if (op == OP_NEG)
        return neg_ok(vals[*nvals - 1], &vals[*nvals - 1]);

    int64_t b = vals[--*nvals];
    int64_t *a = &vals[*nvals - 1];
    switch (op) {
    case OP_ADD: return add_ok(*a, b, a);
    case OP_SUB: return sub_ok(*a, b, a);
    case OP_MUL: return mul_ok(*a, b, a);
    case OP_DIV: return div_ok(*a, b, a);
    case OP_MOD: return mod_ok(*a, b, a);
    default: return false;
    }
}

static bool is_blank(char c)
{
    return c == ' ' || c == '\t';
}

/* Evaluates line[0..len). The evaluator must have capacity >= len. */
static bool evaluate(struct evaluator *ev, const char *line, size_t len, int64_t *result)
{
    int64_t *vals = ev->vals;
    unsigned char *ops = ev->ops;
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
                uint64_t v = 0;
                do {
                    unsigned d = (unsigned)(line[i] - '0');
                    if (v > ((uint64_t)INT64_MAX - d) / 10)
                        return false;
                    v = v * 10 + d;
                    i++;
                } while (i < len && line[i] >= '0' && line[i] <= '9');
                vals[nvals++] = (int64_t)v;
                want_operand = false;
                continue;
            }
            if (c == '-')
                ops[nops++] = OP_NEG;
            else if (c == '(')
                ops[nops++] = OP_LPAREN;
            else
                return false;
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
            while (nops > 0 && ops[nops - 1] != OP_LPAREN)
                if (!apply_top(vals, &nvals, ops, &nops))
                    return false;
            if (nops == 0)
                return false;
            nops--;
            i++;
            continue;
        default:
            return false;
        }

        /* All binary operators are left-associative. */
        int prec = precedence(op);
        while (nops > 0 && precedence((enum op)ops[nops - 1]) >= prec)
            if (!apply_top(vals, &nvals, ops, &nops))
                return false;
        ops[nops++] = (unsigned char)op;
        want_operand = true;
        i++;
    }

    if (want_operand)
        return false;
    while (nops > 0) {
        if (ops[nops - 1] == OP_LPAREN)
            return false;
        if (!apply_top(vals, &nvals, ops, &nops))
            return false;
    }
    *result = vals[0];
    return true;
}

/* ---------- line I/O ---------- */

static bool line_is_blank(const char *line, size_t len)
{
    for (size_t i = 0; i < len; i++)
        if (!is_blank(line[i]))
            return false;
    return true;
}

static bool process_line(struct evaluator *ev, const char *line, size_t len)
{
    if (line_is_blank(line, len))
        return true;
    if (!evaluator_reserve(ev, len))
        return false;
    int64_t value;
    if (evaluate(ev, line, len, &value))
        printf("%lld\n", (long long)value);
    else
        fputs("error\n", stdout);
    return true;
}

int main(void)
{
    static char outbuf[1 << 16];
    setvbuf(stdout, outbuf, _IOFBF, sizeof outbuf);

    struct evaluator ev = {0};
    size_t cap = 1 << 16, len = 0;
    char *buf = malloc(cap);
    if (!buf) {
        fputs("calc: out of memory\n", stderr);
        return EXIT_FAILURE;
    }

    /* buf[0..len) holds unprocessed bytes; complete lines are consumed as
     * they arrive and the remainder is shifted to the front. */
    int status = EXIT_SUCCESS;
    for (;;) {
        if (len == cap) {
            char *grown = realloc(buf, cap * 2);
            if (!grown) {
                status = EXIT_FAILURE;
                break;
            }
            buf = grown;
            cap *= 2;
        }
        size_t n = fread(buf + len, 1, cap - len, stdin);
        if (n == 0) {
            if (len > 0 && !process_line(&ev, buf, len))
                status = EXIT_FAILURE;
            break;
        }

        size_t start = 0, scan = len;
        len += n;
        char *nl;
        while ((nl = memchr(buf + scan, '\n', len - scan)) != NULL) {
            size_t end = (size_t)(nl - buf);
            if (!process_line(&ev, buf + start, end - start)) {
                status = EXIT_FAILURE;
                goto done;
            }
            start = scan = end + 1;
        }
        memmove(buf, buf + start, len - start);
        len -= start;
    }

done:
    if (status != EXIT_SUCCESS)
        fputs("calc: out of memory\n", stderr);
    if (ferror(stdin)) {
        fputs("calc: read error\n", stderr);
        status = EXIT_FAILURE;
    }
    free(buf);
    evaluator_free(&ev);
    if (fflush(stdout) != 0)
        status = EXIT_FAILURE;
    return status;
}
