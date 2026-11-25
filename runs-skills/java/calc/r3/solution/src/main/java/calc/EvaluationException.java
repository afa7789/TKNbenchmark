package calc;

/// Signals that an expression cannot be evaluated: a syntax error, a division by zero,
/// or a result outside the signed 64-bit range.
final class EvaluationException extends Exception {
    private static final long serialVersionUID = 1L;

    EvaluationException(String message) {
        super(message, null, false, false);
    }
}
