package calc;

/// Recursive-descent evaluator for signed 64-bit integer expressions.
///
/// Grammar:
/// ```
/// expr    := term    (('+' | '-') term)*
/// term    := unary   (('*' | '/' | '%') unary)*
/// unary   := '-' unary | primary
/// primary := NUMBER | '(' expr ')'
/// ```
/// Spaces and tabs may appear between tokens. Every arithmetic overflow is an error.
final class Evaluator {
    private final byte[] input;
    private final int end;
    private int pos;

    private Evaluator(byte[] input, int start, int end) {
        this.input = input;
        this.pos = start;
        this.end = end;
    }

    /// Evaluates the expression held in `input[start, end)`.
    static long evaluate(byte[] input, int start, int end) throws EvaluationException {
        Evaluator evaluator = new Evaluator(input, start, end);
        long value = evaluator.expr();
        evaluator.skipBlanks();
        if (evaluator.pos != end) {
            throw new EvaluationException("unexpected character at offset " + (evaluator.pos - start));
        }
        return value;
    }

    private long expr() throws EvaluationException {
        long value = term();
        while (true) {
            int op = peek();
            if (op == '+') {
                pos++;
                value = add(value, term());
            } else if (op == '-') {
                pos++;
                value = subtract(value, term());
            } else {
                return value;
            }
        }
    }

    private long term() throws EvaluationException {
        long value = unary();
        while (true) {
            int op = peek();
            if (op == '*') {
                pos++;
                value = multiply(value, unary());
            } else if (op == '/') {
                pos++;
                value = divide(value, unary());
            } else if (op == '%') {
                pos++;
                value = remainder(value, unary());
            } else {
                return value;
            }
        }
    }

    private long unary() throws EvaluationException {
        // Consume a run of unary minuses iteratively so long chains cannot exhaust the stack.
        int negations = 0;
        while (peek() == '-') {
            pos++;
            negations++;
        }
        long value = primary();
        for (int i = 0; i < negations; i++) {
            value = negate(value);
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
        throw new EvaluationException(c < 0 ? "unexpected end of input" : "unexpected character");
    }

    private long number() throws EvaluationException {
        long value = 0;
        while (pos < end && isDigit(input[pos])) {
            int digit = input[pos++] - '0';
            if (value > (Long.MAX_VALUE - digit) / 10) {
                throw new EvaluationException("literal out of range");
            }
            value = value * 10 + digit;
        }
        return value;
    }

    /// Skips blanks and returns the next character without consuming it, or -1 at end of input.
    private int peek() {
        skipBlanks();
        return pos < end ? input[pos] : -1;
    }

    private void skipBlanks() {
        while (pos < end && (input[pos] == ' ' || input[pos] == '\t')) {
            pos++;
        }
    }

    private static boolean isDigit(int c) {
        return c >= '0' && c <= '9';
    }

    private static long add(long a, long b) throws EvaluationException {
        long r = a + b;
        if (((a ^ r) & (b ^ r)) < 0) {
            throw new EvaluationException("overflow");
        }
        return r;
    }

    private static long subtract(long a, long b) throws EvaluationException {
        long r = a - b;
        if (((a ^ b) & (a ^ r)) < 0) {
            throw new EvaluationException("overflow");
        }
        return r;
    }

    private static long multiply(long a, long b) throws EvaluationException {
        long hi = Math.multiplyHigh(a, b);
        long lo = a * b;
        if (hi != (lo >> 63)) {
            throw new EvaluationException("overflow");
        }
        return lo;
    }

    private static long divide(long a, long b) throws EvaluationException {
        if (b == 0) {
            throw new EvaluationException("division by zero");
        }
        if (a == Long.MIN_VALUE && b == -1) {
            throw new EvaluationException("overflow");
        }
        return a / b;
    }

    private static long remainder(long a, long b) throws EvaluationException {
        if (b == 0) {
            throw new EvaluationException("division by zero");
        }
        return a % b; // Long.MIN_VALUE % -1 == 0 in Java, as required.
    }

    private static long negate(long a) throws EvaluationException {
        if (a == Long.MIN_VALUE) {
            throw new EvaluationException("overflow");
        }
        return -a;
    }
}
