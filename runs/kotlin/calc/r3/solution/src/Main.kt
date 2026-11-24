import java.io.BufferedOutputStream
import kotlin.system.exitProcess

/** Raised for any condition that makes a line evaluate to `error`. */
class CalcException : RuntimeException(null, null, false, false)

/**
 * Recursive-descent evaluator for one expression held in [src][start, end).
 * Works directly on bytes so that arbitrary (non-UTF-8) input is handled safely.
 */
class Parser(private val src: ByteArray, start: Int, private val end: Int) {
    private var pos = start

    fun parseLine(): Long {
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
            val op = peek()
            if (op != STAR && op != SLASH && op != PERCENT) return acc
            pos++
            val rhs = unary()
            acc = when (op) {
                STAR -> checked { Math.multiplyExact(acc, rhs) }
                SLASH -> {
                    if (rhs == 0L || (acc == Long.MIN_VALUE && rhs == -1L)) fail()
                    acc / rhs
                }
                else -> {
                    if (rhs == 0L) fail()
                    if (rhs == -1L) 0L else acc % rhs
                }
            }
        }
    }

    /** Unary minus chains are handled iteratively to avoid deep recursion. */
    private fun unary(): Long {
        var negations = 0
        while (peek() == MINUS) {
            pos++
            negations++
        }
        val value = primary()
        if (negations == 0) return value
        if (value == Long.MIN_VALUE) fail()
        return if (negations % 2 == 0) value else -value
    }

    private fun primary(): Long = when (val c = peek()) {
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
            val digit = src[pos].toInt() - DIGIT_0
            if (value > (Long.MAX_VALUE - digit) / 10) fail()
            value = value * 10 + digit
            pos++
        }
        return value
    }

    /** Skips blanks and returns the next byte, or -1 at end of line. */
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

    private fun fail(): Nothing = throw CalcException()

    companion object {
        private const val PLUS = '+'.code
        private const val MINUS = '-'.code
        private const val STAR = '*'.code
        private const val SLASH = '/'.code
        private const val PERCENT = '%'.code
        private const val LPAREN = '('.code
        private const val RPAREN = ')'.code
        private const val DIGIT_0 = '0'.code
        private const val DIGIT_9 = '9'.code

        fun isBlank(b: Byte): Boolean = b == ' '.code.toByte() || b == '\t'.code.toByte()
    }
}

fun evaluate(src: ByteArray, start: Int, end: Int): String? {
    var i = start
    while (i < end && Parser.isBlank(src[i])) i++
    if (i == end) return null
    return try {
        Parser(src, start, end).parseLine().toString()
    } catch (_: CalcException) {
        "error"
    } catch (_: StackOverflowError) {
        "error"
    }
}

fun run() {
    val input = System.`in`.readBytes()
    val out = BufferedOutputStream(System.out, 1 shl 16)
    var lineStart = 0
    while (lineStart < input.size) {
        var lineEnd = lineStart
        while (lineEnd < input.size && input[lineEnd] != '\n'.code.toByte()) lineEnd++
        evaluate(input, lineStart, lineEnd)?.let {
            out.write(it.toByteArray(Charsets.US_ASCII))
            out.write('\n'.code)
        }
        lineStart = lineEnd + 1
    }
    out.flush()
}

fun main() {
    // Deeply nested parentheses recurse; give the parser a generous stack.
    val worker = Thread(null, ::run, "calc", 1L shl 30)
    worker.start()
    worker.join()
    exitProcess(0)
}
