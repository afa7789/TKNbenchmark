package calc

/**
 * Recursive-descent evaluator for signed 64-bit integer expressions.
 *
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * ```
 *
 * Any syntax error, division by zero, or overflow makes the whole expression invalid.
 */
class Evaluator private constructor(private val src: ByteArray) {
    private var pos = 0

    /** Signals that the expression has no value; carries no stack trace for speed. */
    private object EvaluationException : RuntimeException(null, null, false, false) {
        private fun readResolve(): Any = EvaluationException
    }

    private fun skipSpace() {
        while (pos < src.size && isSpace(src[pos])) pos++
    }

    /** Skips whitespace and returns the next byte without consuming it, or -1 at end of input. */
    private fun peek(): Int {
        skipSpace()
        return if (pos < src.size) src[pos].toInt() else END
    }

    private fun parseExpr(): Long {
        var acc = parseTerm()
        while (true) {
            acc = when (peek()) {
                PLUS -> { pos++; Math.addExact(acc, parseTerm()) }
                MINUS -> { pos++; Math.subtractExact(acc, parseTerm()) }
                else -> return acc
            }
        }
    }

    private fun parseTerm(): Long {
        var acc = parseUnary()
        while (true) {
            acc = when (peek()) {
                STAR -> { pos++; Math.multiplyExact(acc, parseUnary()) }
                SLASH -> { pos++; Math.divideExact(acc, nonZero(parseUnary())) }
                // Long.MIN_VALUE % -1 is 0 on the JVM, which is the required result.
                PERCENT -> { pos++; acc % nonZero(parseUnary()) }
                else -> return acc
            }
        }
    }

    private fun parseUnary(): Long {
        if (peek() == MINUS) {
            pos++
            return Math.negateExact(parseUnary())
        }
        return parsePrimary()
    }

    private fun parsePrimary(): Long {
        val c = peek()
        return when {
            c == LPAREN -> {
                pos++
                val value = parseExpr()
                if (peek() != RPAREN) throw EvaluationException
                pos++
                value
            }
            isDigit(c) -> parseNumber()
            else -> throw EvaluationException
        }
    }

    private fun parseNumber(): Long {
        var value = 0L
        while (pos < src.size && isDigit(src[pos].toInt())) {
            val digit = src[pos] - '0'.code.toByte()
            if (value > (Long.MAX_VALUE - digit) / 10) throw EvaluationException
            value = value * 10 + digit
            pos++
        }
        return value
    }

    companion object {
        private const val END = -1
        private const val PLUS = '+'.code
        private const val MINUS = '-'.code
        private const val STAR = '*'.code
        private const val SLASH = '/'.code
        private const val PERCENT = '%'.code
        private const val LPAREN = '('.code
        private const val RPAREN = ')'.code

        /** Returns the value of the expression, or `null` if it is malformed or not representable. */
        fun evaluate(expression: ByteArray): Long? {
            val evaluator = Evaluator(expression)
            return try {
                val value = evaluator.parseExpr()
                evaluator.skipSpace()
                value.takeIf { evaluator.pos == expression.size }
            } catch (_: EvaluationException) {
                null
            } catch (_: ArithmeticException) {
                null
            }
        }

        /** True if the line holds only spaces and tabs. */
        fun isBlank(line: ByteArray): Boolean = line.all(::isSpace)

        private fun isSpace(b: Byte): Boolean = b == ' '.code.toByte() || b == '\t'.code.toByte()

        private fun isDigit(c: Int): Boolean = c in '0'.code..'9'.code

        private fun nonZero(divisor: Long): Long = if (divisor == 0L) throw EvaluationException else divisor
    }
}
