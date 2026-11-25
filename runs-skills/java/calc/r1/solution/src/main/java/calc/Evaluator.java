package calc;

/// Recursive-descent evaluator for signed 64-bit integer expressions.
///
/// ```
/// expr    := term    (('+' | '-') term)*
/// term    := unary   (('*' | '/' | '%') unary)*
/// unary   := '-' unary | primary
/// primary := NUMBER | '(' expr ')'
/// ```
///
/// Values are computed while parsing; any syntax error, division by zero or
/// 64-bit overflow raises [EvaluationException].
public final class Evaluator {
    private final String input;
    private int pos;

    private Evaluator(String input) {
        this.input = input;
    }

    /// Evaluates a complete expression.
    ///
    /// @param expression the expression text, without a line terminator
    /// @return the value of the expression
    /// @throws EvaluationException if the expression is malformed or its evaluation fails
    public static long evaluate(String expression) throws EvaluationException {
        Evaluator evaluator = new Evaluator(expression);
        long value = evaluator.expr();
        evaluator.skipBlanks();
        if (evaluator.pos != expression.length()) {
            throw evaluator.syntaxError();
        }
        return value;
    }

    private long expr() throws EvaluationException {
        long value = term();
        while (true) {
            char op = peek();
            if (op != '+' && op != '-') {
                return value;
            }
            pos++;
            long rhs = term();
            try {
                value = op == '+' ? Math.addExact(value, rhs) : Math.subtractExact(value, rhs);
            } catch (ArithmeticException _) {
                throw new EvaluationException("overflow");
            }
        }
    }

    private long term() throws EvaluationException {
        long value = unary();
        while (true) {
            char op = peek();
            if (op != '*' && op != '/' && op != '%') {
                return value;
            }
            pos++;
            long rhs = unary();
            value = switch (op) {
                case '*' -> multiply(value, rhs);
                case '/' -> divide(value, rhs);
                default -> remainder(value, rhs);
            };
        }
    }

    private long unary() throws EvaluationException {
        int negations = 0;
        while (peek() == '-') {
            pos++;
            negations++;
        }
        long value = primary();
        for (; negations > 0; negations--) {
            if (value == Long.MIN_VALUE) {
                throw new EvaluationException("overflow");
            }
            value = -value;
        }
        return value;
    }

    private long primary() throws EvaluationException {
        char c = peek();
        if (c == '(') {
            pos++;
            long value = expr();
            if (peek() != ')') {
                throw syntaxError();
            }
            pos++;
            return value;
        }
        if (isDigit(c)) {
            return number();
        }
        throw syntaxError();
    }

    private long number() throws EvaluationException {
        long value = 0;
        while (pos < input.length() && isDigit(input.charAt(pos))) {
            int digit = input.charAt(pos++) - '0';
            if (value > (Long.MAX_VALUE - digit) / 10) {
                throw new EvaluationException("literal out of range");
            }
            value = value * 10 + digit;
        }
        return value;
    }

    private static long multiply(long a, long b) throws EvaluationException {
        try {
            return Math.multiplyExact(a, b);
        } catch (ArithmeticException _) {
            throw new EvaluationException("overflow");
        }
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
        return a % b;
    }

    /// Skips blanks and returns the next character, or `'\0'` at end of input.
    private char peek() {
        skipBlanks();
        return pos < input.length() ? input.charAt(pos) : '\0';
    }

    private void skipBlanks() {
        while (pos < input.length() && isBlank(input.charAt(pos))) {
            pos++;
        }
    }

    private EvaluationException syntaxError() {
        return new EvaluationException("syntax error at position " + pos);
    }

    static boolean isBlank(char c) {
        return c == ' ' || c == '\t';
    }

    private static boolean isDigit(char c) {
        return c >= '0' && c <= '9';
    }
}
