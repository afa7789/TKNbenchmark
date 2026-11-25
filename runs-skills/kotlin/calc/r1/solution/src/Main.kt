import java.io.BufferedOutputStream

/** Raised for any condition that makes a line evaluate to `error`. */
private class EvalException : RuntimeException(null, null, false, false)

/**
 * Recursive-descent evaluator for a single expression line, operating on raw bytes.
 * All arithmetic is checked 64-bit signed; any failure throws [EvalException].
 */
private class Evaluator(private val src: ByteArray, private var pos: Int, private val end: Int) {

    fun evaluate(): Long {
        val value = expr()
        skipBlanks()
        if (pos != end) fail()
        return value
    }

    private fun expr(): Long {
        var acc = term()
        while (true) {
            acc = when (peek()) {
                PLUS -> { pos++; checked { Math.addExact(acc, term()) } }
                MINUS -> { pos++; checked { Math.subtractExact(acc, term()) } }
                else -> return acc
            }
        }
    }

    private fun term(): Long {
        var acc = unary()
        while (true) {
            acc = when (peek()) {
                STAR -> { pos++; checked { Math.multiplyExact(acc, unary()) } }
                SLASH -> { pos++; divide(acc, unary()) }
                PERCENT -> { pos++; remainder(acc, unary()) }
                else -> return acc
            }
        }
    }

    private fun unary(): Long =
        if (peek() == MINUS) {
            pos++
            checked { Math.negateExact(unary()) }
        } else {
            primary()
        }

    private fun primary(): Long = when (peek()) {
        LPAREN -> {
            pos++
            val value = expr()
            if (peek() != RPAREN) fail()
            pos++
            value
        }
        in DIGIT_0..DIGIT_9 -> number()
        else -> fail()
    }

    private fun number(): Long {
        var value = 0L
        while (pos < end && src[pos].toInt() in DIGIT_0..DIGIT_9) {
            val digit = src[pos] - DIGIT_0
            if (value > (Long.MAX_VALUE - digit) / 10) fail()
            value = value * 10 + digit
            pos++
        }
        return value
    }

    private fun divide(a: Long, b: Long): Long {
        if (b == 0L || (a == Long.MIN_VALUE && b == -1L)) fail()
        return a / b
    }

    private fun remainder(a: Long, b: Long): Long {
        if (b == 0L) fail()
        return a % b
    }

    /** Next non-blank byte (consuming blanks), or -1 at end of line. */
    private fun peek(): Int {
        skipBlanks()
        return if (pos < end) src[pos].toInt() else -1
    }

    private fun skipBlanks() {
        while (pos < end && isBlank(src[pos])) pos++
    }

    private inline fun checked(op: () -> Long): Long =
        try {
            op()
        } catch (_: ArithmeticException) {
            fail()
        }

    private fun fail(): Nothing = throw EvalException()

    private companion object {
        const val PLUS = '+'.code
        const val MINUS = '-'.code
        const val STAR = '*'.code
        const val SLASH = '/'.code
        const val PERCENT = '%'.code
        const val LPAREN = '('.code
        const val RPAREN = ')'.code
        const val DIGIT_0 = '0'.code
        const val DIGIT_9 = '9'.code
    }
}

private fun isBlank(b: Byte): Boolean = b == ' '.code.toByte() || b == '\t'.code.toByte()

/** Evaluates `src[start, end)`; returns null for a blank line, else the printed result. */
private fun evaluateLine(src: ByteArray, start: Int, end: Int): String? {
    if ((start..<end).all { isBlank(src[it]) }) return null
    return try {
        Evaluator(src, start, end).evaluate().toString()
    } catch (_: EvalException) {
        "error"
    } catch (_: StackOverflowError) {
        "error"
    }
}

private fun run() {
    val input = System.`in`.readBytes()
    val out = StringBuilder()
    var start = 0
    while (start <= input.size) {
        var end = start
        while (end < input.size && input[end] != '\n'.code.toByte()) end++
        evaluateLine(input, start, end)?.let { out.append(it).append('\n') }
        start = end + 1
    }
    BufferedOutputStream(System.out).use { it.write(out.toString().toByteArray()) }
}

fun main() {
    // Deeply nested expressions recurse deeply; give the parser a generous stack.
    val worker = Thread(null, ::run, "calc", 1L shl 30)
    worker.start()
    worker.join()
}
