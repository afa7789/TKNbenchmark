package calc

/** Signals that an expression could not be evaluated (syntax error, division by zero or overflow). */
class EvaluationException(message: String) : Exception(message, null, false, false)

/**
 * Recursive-descent evaluator for 64-bit signed integer expressions.
 *
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * ```
 *
 * The input is a single line of ASCII bytes; spaces and tabs may separate tokens.
 * Instances are single-use and not thread-safe.
 */
class Evaluator private constructor(
    private val src: ByteArray,
    private var pos: Int,
    private val end: Int,
) {
    private fun expr(): Long {
        var value = term()
        while (true) {
            val op = peek()
            if (op != '+'.code && op != '-'.code) return value
            pos++
            value = apply(op.toChar(), value, term())
        }
    }

    private fun term(): Long {
        var value = unary()
        while (true) {
            val op = peek()
            if (op != '*'.code && op != '/'.code && op != '%'.code) return value
            pos++
            value = apply(op.toChar(), value, unary())
        }
    }

    private fun unary(): Long {
        // Iterate over runs of '-' rather than recursing, so long chains cannot exhaust the stack.
        var negations = 0
        while (peek() == '-'.code) {
            pos++
            negations++
        }
        var value = primary()
        repeat(negations) {
            if (value == Long.MIN_VALUE) fail("overflow")
            value = -value
        }
        return value
    }

    private fun primary(): Long {
        val c = peek()
        return when {
            c == '('.code -> {
                pos++
                val value = expr()
                if (peek() != ')'.code) fail("expected ')'")
                pos++
                value
            }
            isDigit(c) -> number()
            else -> fail("expected operand")
        }
    }

    private fun number(): Long {
        var value = 0L
        var overflow = false
        while (pos < end && isDigit(src[pos].toInt())) {
            val digit = src[pos++] - '0'.code.toByte()
            if (value > (Long.MAX_VALUE - digit) / 10) overflow = true else value = value * 10 + digit
        }
        if (overflow) fail("literal out of range")
        return value
    }

    /** Skips blanks and returns the next byte without consuming it, or -1 at end of input. */
    private fun peek(): Int {
        while (pos < end && isBlank(src[pos])) pos++
        return if (pos < end) src[pos].toInt() else -1
    }

    companion object {
        /** Evaluates `src[start, end)` as a complete expression. */
        @Throws(EvaluationException::class)
        fun evaluate(src: ByteArray, start: Int = 0, end: Int = src.size): Long {
            val evaluator = Evaluator(src, start, end)
            val value = evaluator.expr()
            if (evaluator.peek() != -1) fail("unexpected trailing input")
            return value
        }

        fun isBlank(c: Byte): Boolean = c == ' '.code.toByte() || c == '\t'.code.toByte()

        private fun isDigit(c: Int): Boolean = c in '0'.code..'9'.code

        private fun fail(message: String): Nothing = throw EvaluationException(message)

        private fun apply(op: Char, left: Long, right: Long): Long = try {
            when (op) {
                '+' -> Math.addExact(left, right)
                '-' -> Math.subtractExact(left, right)
                '*' -> Math.multiplyExact(left, right)
                '/' -> Math.divideExact(left, right.nonZero())
                '%' -> left % right.nonZero()
                else -> error("unknown operator $op")
            }
        } catch (e: ArithmeticException) {
            fail("overflow")
        }

        private fun Long.nonZero(): Long = also { if (it == 0L) fail("division by zero") }
    }
}
