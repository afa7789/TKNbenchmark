/** Raised for any syntax, division-by-zero or overflow error; carries no stack trace. */
private class EvalException : RuntimeException(null, null, false, false)

private fun fail(): Nothing = throw EvalException()

/**
 * Recursive-descent evaluator for one line, following the grammar:
 *
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * ```
 */
private class Evaluator(private val src: String) {
    private var pos = 0

    fun evaluate(): Long {
        val value = expr()
        skipBlanks()
        if (pos != src.length) fail()
        return value
    }

    private fun skipBlanks() {
        while (pos < src.length && src[pos].isBlankChar()) pos++
    }

    /** Skips blanks and returns the next character, or `'\u0000'` at end of input. */
    private fun peek(): Char {
        skipBlanks()
        return if (pos < src.length) src[pos] else END
    }

    private fun expr(): Long {
        var acc = term()
        while (true) {
            acc = when (peek()) {
                '+' -> { pos++; overflowChecked { Math.addExact(acc, term()) } }
                '-' -> { pos++; overflowChecked { Math.subtractExact(acc, term()) } }
                else -> return acc
            }
        }
    }

    private fun term(): Long {
        var acc = unary()
        while (true) {
            acc = when (peek()) {
                '*' -> { pos++; overflowChecked { Math.multiplyExact(acc, unary()) } }
                '/' -> {
                    pos++
                    val divisor = unary()
                    if (divisor == 0L || (acc == Long.MIN_VALUE && divisor == -1L)) fail()
                    acc / divisor
                }
                '%' -> {
                    pos++
                    val divisor = unary()
                    if (divisor == 0L) fail()
                    acc % divisor // MIN_VALUE % -1 == 0 on the JVM, as required
                }
                else -> return acc
            }
        }
    }

    private fun unary(): Long {
        if (peek() == '-') {
            pos++
            return overflowChecked { Math.negateExact(unary()) }
        }
        return primary()
    }

    private fun primary(): Long {
        val c = peek()
        return when {
            c == '(' -> {
                pos++
                val value = expr()
                if (peek() != ')') fail()
                pos++
                value
            }
            c in '0'..'9' -> number()
            else -> fail()
        }
    }

    private fun number(): Long {
        var value = 0L
        while (pos < src.length && src[pos] in '0'..'9') {
            val digit = (src[pos] - '0').toLong()
            if (value > (Long.MAX_VALUE - digit) / 10) fail()
            value = value * 10 + digit
            pos++
        }
        return value
    }

    private inline fun overflowChecked(op: () -> Long): Long =
        try {
            op()
        } catch (_: ArithmeticException) {
            fail()
        }

    private companion object {
        const val END = '\u0000'
    }
}

private fun Char.isBlankChar() = this == ' ' || this == '\t'

/** Returns the line's value as text, `"error"`, or `null` for a blank line. */
fun evaluateLine(line: String): String? {
    if (line.all { it.isBlankChar() }) return null
    return try {
        Evaluator(line).evaluate().toString()
    } catch (_: EvalException) {
        "error"
    } catch (_: StackOverflowError) {
        "error"
    }
}

private fun run() {
    // Lines end with '\n' only; any other control character (such as '\r') is a syntax error.
    val input = String(System.`in`.readAllBytes(), Charsets.ISO_8859_1)
    val out = StringBuilder()
    for (line in input.splitToSequence('\n')) {
        evaluateLine(line)?.let { out.append(it).append('\n') }
    }
    System.out.write(out.toString().toByteArray(Charsets.ISO_8859_1))
    System.out.flush()
}

fun main() {
    // Deeply nested parentheses recurse deeply; give the parser a generous stack.
    val worker = Thread(null, ::run, "calc", 1L shl 30)
    worker.start()
    worker.join()
}
