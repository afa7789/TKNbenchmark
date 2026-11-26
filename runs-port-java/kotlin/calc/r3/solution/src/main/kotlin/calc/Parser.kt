package calc

/**
 * Recursive-descent evaluator for signed 64-bit integer expressions.
 *
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * NUMBER  := [0-9]+
 * ```
 *
 * Spaces and tabs are permitted between tokens. All arithmetic is overflow-checked.
 */
class Parser private constructor(private val src: String) {

    private var pos = 0

    private fun parseAll(): Long {
        val value = expr()
        skipBlanks()
        if (pos != src.length) throw CalcException("unexpected character at $pos")
        return value
    }

    private fun expr(): Long {
        var value = term()
        while (true) {
            val op = peek()
            if (op != '+' && op != '-') return value
            pos++
            value = apply(op, value, term())
        }
    }

    private fun term(): Long {
        var value = unary()
        while (true) {
            val op = peek()
            if (op != '*' && op != '/' && op != '%') return value
            pos++
            value = apply(op, value, unary())
        }
    }

    private fun unary(): Long {
        if (peek() != '-') return primary()
        pos++
        val operand = unary()
        if (operand == Long.MIN_VALUE) throw CalcException("overflow in negation")
        return -operand
    }

    private fun primary(): Long {
        val c = peek()
        return when {
            c == '(' -> {
                pos++
                val value = expr()
                if (peek() != ')') throw CalcException("expected ')' at $pos")
                pos++
                value
            }
            c != null && c.isAsciiDigit() -> number()
            else -> throw CalcException("expected operand at $pos")
        }
    }

    private fun number(): Long {
        var value = 0L
        while (pos < src.length && src[pos].isAsciiDigit()) {
            val digit = src[pos++] - '0'
            if (value > (Long.MAX_VALUE - digit) / 10) throw CalcException("literal out of range")
            value = value * 10 + digit
        }
        return value
    }

    /** Skips blanks and returns the next character without consuming it, or `null` at end of input. */
    private fun peek(): Char? {
        skipBlanks()
        return src.getOrNull(pos)
    }

    private fun skipBlanks() {
        while (pos < src.length && src[pos].isBlankChar()) pos++
    }

    companion object {
        /** Evaluates a complete expression, throwing [CalcException] on any error. */
        fun evaluate(expression: String): Long = Parser(expression).parseAll()

        /** Applies a binary operator with exact 64-bit semantics. */
        private fun apply(op: Char, left: Long, right: Long): Long = try {
            when (op) {
                '+' -> Math.addExact(left, right)
                '-' -> Math.subtractExact(left, right)
                '*' -> Math.multiplyExact(left, right)
                '/' -> Math.divideExact(left, requireNonZero(right))
                // Long.MIN_VALUE % -1 is 0 on the JVM, matching the specification.
                '%' -> left % requireNonZero(right)
                else -> throw IllegalArgumentException("unknown operator $op")
            }
        } catch (e: ArithmeticException) {
            throw CalcException("overflow")
        }

        private fun requireNonZero(divisor: Long): Long =
            if (divisor == 0L) throw CalcException("division by zero") else divisor

        private fun Char.isAsciiDigit(): Boolean = this in '0'..'9'
    }
}

/** True for the only whitespace the grammar allows between tokens: space and tab. */
internal fun Char.isBlankChar(): Boolean = this == ' ' || this == '\t'
