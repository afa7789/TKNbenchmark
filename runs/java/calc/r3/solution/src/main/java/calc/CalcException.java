package calc;

/** Signals any failure while evaluating an expression: syntax, division by zero, or overflow. */
public final class CalcException extends Exception {

    private static final long serialVersionUID = 1L;

    public CalcException(String message) {
        super(message, null, false, false);
    }
}
