package calc;

import java.util.Optional;

/**
 * Recursive-descent evaluator for signed 64-bit integer expressions.
 *
 * <pre>
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * </pre>
 *
 * Any syntax error, division by zero, or overflow makes the whole expression invalid.
 */
public final class Evaluator {

    /** Signals that the expression has no value; carries no stack trace for speed. */
    private static final class EvaluationException extends RuntimeException {
        private static final EvaluationException INSTANCE = new EvaluationException();

        private EvaluationException() {
            super(null, null, false, false);
        }
    }

    private final byte[] src;
    private int pos;

    private Evaluator(byte[] src) {
        this.src = src;
    }

    /** Returns the value of the expression, or empty if it is malformed or not representable. */
    public static Optional<Long> evaluate(byte[] expression) {
        Evaluator evaluator = new Evaluator(expression);
        try {
            long value = evaluator.parseExpr();
            evaluator.skipSpace();
            if (evaluator.pos != expression.length) {
                return Optional.empty();
            }
            return Optional.of(value);
        } catch (EvaluationException | ArithmeticException e) {
            return Optional.empty();
        }
    }

    /** True if the line holds only spaces and tabs. */
    public static boolean isBlank(byte[] line) {
        for (byte b : line) {
            if (!isSpace(b)) {
                return false;
            }
        }
        return true;
    }

    private static boolean isSpace(byte b) {
        return b == ' ' || b == '\t';
    }

    private static EvaluationException fail() {
        return EvaluationException.INSTANCE;
    }

    private void skipSpace() {
        while (pos < src.length && isSpace(src[pos])) {
            pos++;
        }
    }

    /** Skips whitespace and returns the next byte without consuming it, or -1 at end of input. */
    private int peek() {
        skipSpace();
        return pos < src.length ? src[pos] : -1;
    }

    private long parseExpr() {
        long acc = parseTerm();
        while (true) {
            int c = peek();
            if (c == '+') {
                pos++;
                acc = Math.addExact(acc, parseTerm());
            } else if (c == '-') {
                pos++;
                acc = Math.subtractExact(acc, parseTerm());
            } else {
                return acc;
            }
        }
    }

    private long parseTerm() {
        long acc = parseUnary();
        while (true) {
            int c = peek();
            if (c == '*') {
                pos++;
                acc = Math.multiplyExact(acc, parseUnary());
            } else if (c == '/') {
                pos++;
                long divisor = parseUnary();
                if (divisor == 0) {
                    throw fail();
                }
                acc = Math.divideExact(acc, divisor);
            } else if (c == '%') {
                pos++;
                long divisor = parseUnary();
                if (divisor == 0) {
                    throw fail();
                }
                // Long.MIN_VALUE % -1 is 0 in Java, which is the required result.
                acc %= divisor;
            } else {
                return acc;
            }
        }
    }

    private long parseUnary() {
        if (peek() == '-') {
            pos++;
            return Math.negateExact(parseUnary());
        }
        return parsePrimary();
    }

    private long parsePrimary() {
        int c = peek();
        if (c == '(') {
            pos++;
            long value = parseExpr();
            if (peek() != ')') {
                throw fail();
            }
            pos++;
            return value;
        }
        if (c >= '0' && c <= '9') {
            return parseNumber();
        }
        throw fail();
    }

    private long parseNumber() {
        long value = 0;
        while (pos < src.length && src[pos] >= '0' && src[pos] <= '9') {
            int digit = src[pos] - '0';
            if (value > (Long.MAX_VALUE - digit) / 10) {
                throw fail();
            }
            value = value * 10 + digit;
            pos++;
        }
        return value;
    }
}
