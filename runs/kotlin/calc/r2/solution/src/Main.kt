import java.io.PrintWriter
import kotlin.system.exitProcess

/** Raised when an expression is malformed or its evaluation fails (division by zero, overflow). */
class CalcException(message: String) : Exception(message, null, false, false)

/**
 * Recursive-descent evaluator for one line, computing values while parsing.
 *
 * Grammar:
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * ```
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

    private fun expect(c: Char) {
        if (peek() != c) throw CalcException("expected '$c' at $pos")
        pos++
    }

    private fun parseExpr(): Long {
        var acc = parseTerm()
        while (true) {
            when (peek()) {
                '+' -> { pos++; acc = arith { Math.addExact(acc, parseTerm()) } }
                '-' -> { pos++; acc = arith { Math.subtractExact(acc, parseTerm()) } }
                else -> return acc
            }
        }
    }

    private fun parseTerm(): Long {
        var acc = parseUnary()
        while (true) {
            when (peek()) {
                '*' -> { pos++; acc = arith { Math.multiplyExact(acc, parseUnary()) } }
                '/' -> { pos++; acc = divide(acc, parseUnary()) }
                '%' -> { pos++; acc = remainder(acc, parseUnary()) }
                else -> return acc
            }
        }
    }

    private fun parseUnary(): Long {
        // Iterate over chained minus signs to keep recursion depth bounded by parentheses only.
        var negations = 0
        while (peek() == '-') {
            pos++
            negations++
        }
        var value = parsePrimary()
        repeat(negations) { value = arith { Math.negateExact(value) } }
        return value
    }

    private fun parsePrimary(): Long = when (val c = peek()) {
        '(' -> {
            pos++
            parseExpr().also { expect(')') }
        }
        in '0'..'9' -> parseNumber()
        else -> throw CalcException(if (c == null) "unexpected end of input" else "unexpected '$c' at $pos")
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

    private inline fun arith(op: () -> Long): Long =
        try {
            op()
        } catch (e: ArithmeticException) {
            throw CalcException("overflow")
        }

    companion object {
        /** Evaluates [line], throwing [CalcException] on any syntax or arithmetic error. */
        fun evaluate(line: String): Long {
            val evaluator = Evaluator(line)
            val result = evaluator.parseExpr()
            if (evaluator.peek() != null) throw CalcException("trailing input at ${evaluator.pos}")
            return result
        }
    }
}

private fun isBlank(line: String) = line.all { it == ' ' || it == '\t' }

private fun run() {
    // Only '\n' terminates a line; any other control character (e.g. '\r') is a syntax error.
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val out = PrintWriter(System.out.bufferedWriter(Charsets.ISO_8859_1), false)
    for (line in input.splitToSequence('\n')) {
        if (isBlank(line)) continue
        val result = try {
            Evaluator.evaluate(line).toString()
        } catch (e: CalcException) {
            "error"
        } catch (e: StackOverflowError) {
            "error"
        }
        out.println(result)
    }
    out.flush()
}

fun main() {
    // Deeply nested parentheses recurse; run on a thread with a generous stack.
    val worker = Thread(null, ::run, "calc", 1L shl 30)
    worker.start()
    worker.join()
    exitProcess(0)
}
