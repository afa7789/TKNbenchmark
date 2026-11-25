
/** Raised for any evaluation failure; stackless because it is part of normal control flow. */
class CalcException(message: String) : RuntimeException(message, null, false, false)

/**
 * Recursive-descent evaluator for one line of the grammar:
 *
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * ```
 *
 * All arithmetic is checked signed 64-bit.
 */
class Evaluator private constructor(private val src: String) {
    private var pos = 0

    private fun skipBlanks() {
        while (pos < src.length && (src[pos] == ' ' || src[pos] == '\t')) pos++
    }

    private fun peek(): Char? {
        skipBlanks()
        return if (pos < src.length) src[pos] else null
    }

    private fun parseExpr(): Long {
        var acc = parseTerm()
        while (true) {
            when (peek()) {
                '+' -> { pos++; acc = Math.addExact(acc, parseTerm()) }
                '-' -> { pos++; acc = Math.subtractExact(acc, parseTerm()) }
                else -> return acc
            }
        }
    }

    private fun parseTerm(): Long {
        var acc = parseUnary()
        while (true) {
            when (peek()) {
                '*' -> { pos++; acc = Math.multiplyExact(acc, parseUnary()) }
                '/' -> { pos++; acc = divide(acc, parseUnary()) }
                '%' -> { pos++; acc = remainder(acc, parseUnary()) }
                else -> return acc
            }
        }
    }

    private fun parseUnary(): Long {
        // Iterate over the minus signs so long chains do not consume stack.
        var negations = 0
        while (peek() == '-') {
            pos++
            negations++
        }
        var value = parsePrimary()
        repeat(negations) { value = Math.negateExact(value) }
        return value
    }

    private fun parsePrimary(): Long {
        val c = peek() ?: throw CalcException("unexpected end of input")
        return when {
            c == '(' -> {
                pos++
                val inner = parseExpr()
                if (peek() != ')') throw CalcException("expected ')'")
                pos++
                inner
            }
            c in '0'..'9' -> parseNumber()
            else -> throw CalcException("unexpected '$c'")
        }
    }

    private fun parseNumber(): Long {
        var value = 0L
        while (pos < src.length && src[pos] in '0'..'9') {
            val digit = (src[pos] - '0').toLong()
            if (value > (Long.MAX_VALUE - digit) / 10) throw CalcException("literal out of range")
            value = value * 10 + digit
            pos++
        }
        return value
    }

    private fun divide(a: Long, b: Long): Long {
        if (b == 0L) throw CalcException("division by zero")
        if (a == Long.MIN_VALUE && b == -1L) throw CalcException("overflow")
        return a / b
    }

    private fun remainder(a: Long, b: Long): Long {
        if (b == 0L) throw CalcException("division by zero")
        return a % b
    }

    private fun evaluateAll(): Long {
        val result = parseExpr()
        if (peek() != null) throw CalcException("trailing input")
        return result
    }

    companion object {
        /** Returns the value of [line], or `null` if it is invalid or fails to evaluate. */
        fun evaluate(line: String): Long? = try {
            Evaluator(line).evaluateAll()
        } catch (_: CalcException) {
            null
        } catch (_: ArithmeticException) {
            null
        }
    }
}

private fun String.isBlankLine(): Boolean = all { it == ' ' || it == '\t' }

private fun run() {
    // Lines end with '\n' only; any other control character (e.g. '\r') is a syntax error.
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val out = StringBuilder()
    for (line in input.splitToSequence('\n')) {
        if (line.isBlankLine()) continue
        out.append(Evaluator.evaluate(line)?.toString() ?: "error").append('\n')
    }
    System.out.write(out.toString().toByteArray(Charsets.ISO_8859_1))
    System.out.flush()
}

fun main() {
    // Deeply nested parentheses recurse; give the parser a generous stack.
    val worker = Thread(null, ::run, "calc", 1L shl 30)
    worker.start()
    worker.join()
}
