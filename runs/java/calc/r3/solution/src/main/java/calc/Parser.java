package calc;

/**
 * Recursive-descent evaluator for signed 64-bit integer expressions.
 *
 * <pre>
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * NUMBER  := [0-9]+
 * </pre>
 *
 * Spaces and tabs are permitted between tokens. All arithmetic is overflow-checked.
 */
public final class Parser {

    private final String src;
    private int pos;

    private Parser(String src) {
        this.src = src;
    }

    /** Evaluates a complete expression, throwing {@link CalcException} on any error. */
    public static long evaluate(String expression) throws CalcException {
        Parser parser = new Parser(expression);
        long value = parser.expr();
        parser.skipBlanks();
        if (parser.pos != parser.src.length()) {
            throw new CalcException("unexpected character at " + parser.pos);
        }
        return value;
    }

    private long expr() throws CalcException {
        long value = term();
        while (true) {
            int op = peek();
            if (op == '+') {
                pos++;
                value = apply('+', value, term());
            } else if (op == '-') {
                pos++;
                value = apply('-', value, term());
            } else {
                return value;
            }
        }
    }

    private long term() throws CalcException {
        long value = unary();
        while (true) {
            int op = peek();
            if (op == '*' || op == '/' || op == '%') {
                pos++;
                value = apply((char) op, value, unary());
            } else {
                return value;
            }
        }
    }

    private long unary() throws CalcException {
        if (peek() == '-') {
            pos++;
            long operand = unary();
            if (operand == Long.MIN_VALUE) {
                throw new CalcException("overflow in negation");
            }
            return -operand;
        }
        return primary();
    }

    private long primary() throws CalcException {
        int c = peek();
        if (c == '(') {
            pos++;
            long value = expr();
            if (peek() != ')') {
                throw new CalcException("expected ')' at " + pos);
            }
            pos++;
            return value;
        }
        if (isDigit(c)) {
            return number();
        }
        throw new CalcException("expected operand at " + pos);
    }

    private long number() throws CalcException {
        long value = 0;
        while (pos < src.length() && isDigit(src.charAt(pos))) {
            int digit = src.charAt(pos++) - '0';
            if (value > (Long.MAX_VALUE - digit) / 10) {
                throw new CalcException("literal out of range");
            }
            value = value * 10 + digit;
        }
        return value;
    }

    /** Applies a binary operator with exact 64-bit semantics. */
    private static long apply(char op, long left, long right) throws CalcException {
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
                    // Long.MIN_VALUE % -1 is 0 in Java, matching the specification.
                    yield left % right;
                }
                default -> throw new IllegalArgumentException("unknown operator " + op);
            };
        } catch (ArithmeticException e) {
            throw new CalcException("overflow");
        }
    }

    private static void requireNonZero(long divisor) throws CalcException {
        if (divisor == 0) {
            throw new CalcException("division by zero");
        }
    }

    /** Skips blanks and returns the next character without consuming it, or -1 at end of input. */
    private int peek() {
        skipBlanks();
        return pos < src.length() ? src.charAt(pos) : -1;
    }

    private void skipBlanks() {
        while (pos < src.length()) {
            char c = src.charAt(pos);
            if (c != ' ' && c != '\t') {
                return;
            }
            pos++;
        }
    }

    private static boolean isDigit(int c) {
        return c >= '0' && c <= '9';
    }
}
