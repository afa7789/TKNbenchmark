package calc;

/// Signals that an expression cannot be evaluated: a syntax error, division by zero, or overflow.
final class EvaluationException extends Exception {
    EvaluationException(String message) {
        super(message, null, false, false);
    }
}
