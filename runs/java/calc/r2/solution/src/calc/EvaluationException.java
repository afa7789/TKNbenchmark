package calc;

/** Signals that an expression could not be evaluated (syntax error, division by zero or overflow). */
final class EvaluationException extends Exception {
    private static final long serialVersionUID = 1L;

    EvaluationException(String message) {
        super(message, null, false, false);
    }
}
