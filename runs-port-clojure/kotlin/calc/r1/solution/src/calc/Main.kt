// 64-bit signed integer expression evaluator.
// Reads one expression per line from stdin and prints its value or `error`.
package calc

import java.io.BufferedWriter
import java.io.InputStream
import java.io.OutputStreamWriter
import kotlin.system.exitProcess

/** Raised for any condition that makes a line evaluate to `error`. */
class CalcException(message: String) : RuntimeException(message, null, false, false)

private fun Char.isBlank(): Boolean = this == ' ' || this == '\t'

private fun Char.isAsciiDigit(): Boolean = this in '0'..'9'

/**
 * Recursive-descent parser that evaluates while parsing:
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
        if (peek() != END) fail("unexpected '${src[pos]}' at $pos")
        return value
    }

    /** Skips blanks and returns the next character, or [END] at end of input. */
    private fun peek(): Char {
        while (pos < src.length && src[pos].isBlank()) pos++
        return if (pos < src.length) src[pos] else END
    }

    private fun expr(): Long {
        var acc = term()
        while (true) {
            acc = when (peek()) {
                '+' -> { pos++; val rhs = term(); checked { Math.addExact(acc, rhs) } }
                '-' -> { pos++; val rhs = term(); checked { Math.subtractExact(acc, rhs) } }
                else -> return acc
            }
        }
    }

    private fun term(): Long {
        var acc = unary()
        while (true) {
            acc = when (peek()) {
                '*' -> { pos++; val rhs = unary(); checked { Math.multiplyExact(acc, rhs) } }
                '/' -> { pos++; divide(acc, unary()) }
                '%' -> { pos++; remainder(acc, unary()) }
                else -> return acc
            }
        }
    }

    private fun unary(): Long =
        if (peek() == '-') {
            pos++
            val operand = unary()
            checked { Math.negateExact(operand) }
        } else {
            primary()
        }

    private fun primary(): Long = when (val c = peek()) {
        '(' -> {
            pos++
            val value = expr()
            if (peek() != ')') fail("expected ')' at $pos")
            pos++
            value
        }
        else -> if (c.isAsciiDigit()) number() else fail("unexpected token at $pos")
    }

    private fun number(): Long {
        val start = pos
        while (pos < src.length && src[pos].isAsciiDigit()) pos++
        return src.substring(start, pos).toLongOrNull() ?: fail("literal out of range")
    }

    private fun divide(a: Long, b: Long): Long {
        if (b == 0L) fail("division by zero")
        if (a == Long.MIN_VALUE && b == -1L) fail("overflow")
        return a / b
    }

    // JVM remainder follows the dividend's sign and yields 0 for MIN_VALUE % -1.
    private fun remainder(a: Long, b: Long): Long {
        if (b == 0L) fail("division by zero")
        return a % b
    }

    private companion object {
        const val END = '\u0000'
    }
}

private inline fun checked(op: () -> Long): Long =
    try {
        op()
    } catch (e: ArithmeticException) {
        throw CalcException("overflow")
    }

private fun fail(reason: String): Nothing = throw CalcException(reason)

/** Returns the output for one input line, or null for a blank line. */
fun lineResult(line: String): String? {
    if (line.all { it.isBlank() }) return null
    return try {
        Evaluator(line).evaluate().toString()
    } catch (_: CalcException) {
        "error"
    } catch (_: StackOverflowError) {
        "error"
    }
}

/** Splits [input] on '\n' only, so a stray '\r' is reported as a syntax error. */
private fun forEachLine(input: InputStream, action: (String) -> Unit) {
    val reader = input.bufferedReader(Charsets.ISO_8859_1)
    val line = StringBuilder()
    while (true) {
        val c = reader.read()
        when {
            c < 0 -> {
                if (line.isNotEmpty()) action(line.toString())
                return
            }
            c == '\n'.code -> {
                action(line.toString())
                line.setLength(0)
            }
            else -> line.append(c.toChar())
        }
    }
}

private fun run() {
    val out = BufferedWriter(OutputStreamWriter(System.out, Charsets.ISO_8859_1), 1 shl 16)
    forEachLine(System.`in`) { line ->
        lineResult(line)?.let {
            out.write(it)
            out.write("\n")
        }
    }
    out.flush()
}

fun main() {
    // Run on a thread with a large stack so deeply nested input is handled.
    val worker = Thread(null, ::run, "calc", 512L * 1024 * 1024)
    worker.start()
    worker.join()
    exitProcess(0)
}
