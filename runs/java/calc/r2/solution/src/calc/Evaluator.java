package calc;

/**
 * Recursive-descent evaluator for 64-bit signed integer expressions.
 *
 * <pre>
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * </pre>
 *
 * The input is a single line as ASCII bytes; spaces and tabs may separate tokens.
 * Instances are single-use and not thread-safe.
 */
final class Evaluator {
    private final byte[] src;
    private final int end;
    private int pos;

    private Evaluator(byte[] src, int start, int end) {
        this.src = src;
        this.pos = start;
        this.end = end;
    }

    /** Evaluates {@code src[start, end)} as a complete expression. */
    static long evaluate(byte[] src, int start, int end) throws EvaluationException {
        Evaluator evaluator = new Evaluator(src, start, end);
        long value = evaluator.expr();
        if (evaluator.peek() != -1) {
            throw new EvaluationException("unexpected trailing input");
        }
        return value;
    }

    private long expr() throws EvaluationException {
        long value = term();
        while (true) {
                int c = peek();
            if (c == '+') {
                pos++;
                value = apply('+', value, term());
            } else if (c == '-') {
                pos++;
                value = apply('-', value, term());
            } else {
                return value;
            }
        }
    }

    private long term() throws EvaluationException {
        long value = unary();
        while (true) {
            int c = peek();
            if (c == '*' || c == '/' || c == '%') {
                pos++;
                value = apply((char) c, value, unary());
            } else {
                return value;
            }
        }
    }

    private long unary() throws EvaluationException {
        // Iterate over runs of '-' rather than recursing, so long chains cannot exhaust the stack.
        int negations = 0;
        while (peek() == '-') {
            pos++;
            negations++;
        }
        long value = primary();
        for (int i = 0; i < negations; i++) {
            if (value == Long.MIN_VALUE) {
                throw new EvaluationException("overflow");
            }
            value = -value;
        }
        return value;
    }

    private long primary() throws EvaluationException {
        int c = peek();
        if (c == '(') {
            pos++;
            long value = expr();
            if (peek() != ')') {
                throw new EvaluationException("expected ')'");
            }
            pos++;
            return value;
        }
        if (isDigit(c)) {
            return number();
        }
        throw new EvaluationException("expected operand");
    }

    private long number() throws EvaluationException {
        long value = 0;
        boolean overflow = false;
        while (pos < end && isDigit(src[pos])) {
            int digit = src[pos++] - '0';
            if (value > (Long.MAX_VALUE - digit) / 10) {
                overflow = true;
            } else {
                value = value * 10 + digit;
            }
        }
        if (overflow) {
            throw new EvaluationException("literal out of range");
        }
        return value;
    }

    private static long apply(char op, long left, long right) throws EvaluationException {
        try {
            return switch (op) {
                case '+' -> Math.addExact(left, right);
                case '-' -> Math.subtractExact(left, right);
                case '*' -> Math.multiplyExact(left, right);
                case '/' -> {
                    requireNonZero(right);
                    yield Math.divideExact(left, right);
                }
                case '%' -> {
                    requireNonZero(right);
                    yield left % right;
                }
                default -> throw new IllegalArgumentException("unknown operator " + op);
            };
        } catch (ArithmeticException e) {
            throw new EvaluationException("overflow");
        }
    }

    private static void requireNonZero(long divisor) throws EvaluationException {
        if (divisor == 0) {
            throw new EvaluationException("division by zero");
        }
    }

    /** Skips blanks and returns the next byte without consuming it, or -1 at end of input. */
    private int peek() {
        while (pos < end && isBlank(src[pos])) {
            pos++;
        }
        return pos < end ? src[pos] : -1;
    }

    static boolean isBlank(int c) {
        return c == ' ' || c == '\t';
    }

    private static boolean isDigit(int c) {
        return c >= '0' && c <= '9';
    }
}
