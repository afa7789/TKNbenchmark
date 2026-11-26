package calc

/** Signals any failure while evaluating an expression: syntax, division by zero, or overflow. */
class CalcException(message: String) : RuntimeException(message, null, false, false)
