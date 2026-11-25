package calc;

/// Signals that an expression cannot be evaluated: a syntax error, division by zero or overflow.
public final class EvaluationException extends Exception {
    private static final long serialVersionUID = 1L;

    public EvaluationException(String message) {
        super(message, null, false, false);
    }
}
