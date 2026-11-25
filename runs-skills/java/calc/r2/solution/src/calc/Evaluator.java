package calc;

/// Recursive-descent evaluator for signed 64-bit integer expressions.
///
/// Grammar (spaces and tabs may appear between tokens):
/// ```
/// expr    := term    (('+' | '-') term)*
/// term    := unary   (('*' | '/' | '%') unary)*
/// unary   := '-' unary | primary
/// primary := NUMBER | '(' expr ')'
/// ```
/// The input is a range of bytes, so any non-ASCII byte is simply a syntax error.
final class Evaluator {
    private final byte[] buf;
    private final int end;
    private int pos;

    private Evaluator(byte[] buf, int start, int end) {
        this.buf = buf;
        this.pos = start;
        this.end = end;
    }

    /// Evaluates the expression held in `buf[start, end)`.
    static long evaluate(byte[] buf, int start, int end) throws EvaluationException {
        Evaluator evaluator = new Evaluator(buf, start, end);
        long value = evaluator.expr();
        if (evaluator.peek() != -1) {
            throw new EvaluationException("unexpected character at offset " + (evaluator.pos - start));
        }
        return value;
    }

    private long expr() throws EvaluationException {
        long value = term();
        while (true) {
            int c = peek();
            if (c != '+' && c != '-') {
                return value;
            }
            pos++;
            value = apply((char) c, value, term());
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
        if (peek() == '-') {
            pos++;
            long operand = unary();
            if (operand == Long.MIN_VALUE) {
                throw new EvaluationException("overflow");
            }
            return -operand;
        }
        return primary();
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
        if (c >= '0' && c <= '9') {
            return number();
        }
        throw new EvaluationException("expected operand");
    }

    private long number() throws EvaluationException {
        long value = 0;
        while (pos < end && buf[pos] >= '0' && buf[pos] <= '9') {
            int digit = buf[pos++] - '0';
            if (value > (Long.MAX_VALUE - digit) / 10) {
                throw new EvaluationException("literal out of range");
            }
            value = value * 10 + digit;
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
                    if (right == 0) {
                        throw new EvaluationException("division by zero");
                    }
                    yield Math.divideExact(left, right);
                }
                case '%' -> {
                    if (right == 0) {
                        throw new EvaluationException("division by zero");
                    }
                    yield left % right; // Long.MIN_VALUE % -1 is 0, not an overflow
                }
                default -> throw new IllegalArgumentException("unknown operator: " + op);
            };
        } catch (ArithmeticException e) {
            throw new EvaluationException("overflow");
        }
    }

    /// Skips blanks and returns the next byte without consuming it, or -1 at end of input.
    private int peek() {
        while (pos < end && (buf[pos] == ' ' || buf[pos] == '\t')) {
            pos++;
        }
        return pos < end ? buf[pos] & 0xFF : -1;
    }
}
