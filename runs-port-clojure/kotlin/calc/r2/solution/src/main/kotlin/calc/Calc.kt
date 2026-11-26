package calc

import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import kotlin.system.exitProcess

/** Signals that the current line cannot be evaluated. */
class EvalException(message: String) : RuntimeException(message, null, false, false)

private fun fail(reason: String): Nothing = throw EvalException(reason)

private fun Char.isBlankChar(): Boolean = this == ' ' || this == '\t'
private fun Char.isAsciiDigit(): Boolean = this in '0'..'9'

/** Lexical tokens: integer literals and single-character operators/parentheses. */
sealed interface Token {
    data class Number(val value: Long) : Token
    data class Symbol(val char: Char) : Token
}

private const val SYMBOLS = "+-*/%()"

/** Splits a line into tokens. Throws [EvalException] on any character outside the grammar. */
fun tokenize(s: String): List<Token> {
    val tokens = ArrayList<Token>()
    var i = 0
    while (i < s.length) {
        val c = s[i]
        when {
            c.isBlankChar() -> i++
            c.isAsciiDigit() -> {
                var end = i + 1
                while (end < s.length && s[end].isAsciiDigit()) end++
                val value = s.substring(i, end).toLongOrNull() ?: fail("integer literal out of range")
                tokens += Token.Number(value)
                i = end
            }
            c in SYMBOLS -> {
                tokens += Token.Symbol(c)
                i++
            }
            else -> fail("unexpected character '$c'")
        }
    }
    return tokens
}

/**
 * Recursive-descent parser/evaluator over a token list.
 *
 * Grammar:
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * ```
 * Arithmetic is checked: overflow raises [ArithmeticException].
 */
private class Evaluator(private val tokens: List<Token>) {
    private var pos = 0

    private fun peekSymbol(): Char? = (tokens.getOrNull(pos) as? Token.Symbol)?.char

    fun evaluate(): Long {
        val value = expr()
        if (pos != tokens.size) fail("unexpected trailing input")
        return value
    }

    private fun expr(): Long {
        var acc = term()
        while (true) {
            val op = peekSymbol()
            acc = when (op) {
                '+' -> { pos++; Math.addExact(acc, term()) }
                '-' -> { pos++; Math.subtractExact(acc, term()) }
                else -> return acc
            }
        }
    }

    private fun term(): Long {
        var acc = unary()
        while (true) {
            val op = peekSymbol()
            acc = when (op) {
                '*' -> { pos++; Math.multiplyExact(acc, unary()) }
                '/' -> { pos++; checkedQuot(acc, unary()) }
                '%' -> { pos++; checkedRem(acc, unary()) }
                else -> return acc
            }
        }
    }

    private fun unary(): Long =
        if (peekSymbol() == '-') {
            pos++
            Math.negateExact(unary())
        } else {
            primary()
        }

    private fun primary(): Long =
        when (val t = tokens.getOrNull(pos)) {
            is Token.Number -> {
                pos++
                t.value
            }
            Token.Symbol('(') -> {
                pos++
                val value = expr()
                if (peekSymbol() != ')') fail("expected )")
                pos++
                value
            }
            else -> fail("expected operand")
        }

    private fun checkedQuot(a: Long, b: Long): Long = when {
        b == 0L -> fail("division by zero")
        a == Long.MIN_VALUE && b == -1L -> fail("overflow")
        else -> a / b
    }

    private fun checkedRem(a: Long, b: Long): Long =
        if (b == 0L) fail("division by zero") else a % b
}

/** Evaluates an expression string, throwing [EvalException] or [ArithmeticException] on failure. */
fun evaluate(s: String): Long = Evaluator(tokenize(s)).evaluate()

/** Returns the output for one input line: the value, "error", or null for a blank line. */
fun evalLine(line: String): String? {
    if (line.all { it.isBlankChar() }) return null
    return try {
        evaluate(line).toString()
    } catch (_: EvalException) {
        "error"
    } catch (_: ArithmeticException) {
        "error"
    }
}

/** Reads expressions from stdin line by line and writes results to stdout. */
fun run() {
    val reader = BufferedReader(InputStreamReader(System.`in`, Charsets.ISO_8859_1), 1 shl 16)
    val writer = BufferedWriter(OutputStreamWriter(System.out, Charsets.ISO_8859_1), 1 shl 16)
    writer.use { out ->
        reader.lineSequence().forEach { line ->
            evalLine(line)?.let {
                out.write(it)
                out.write('\n'.code)
            }
        }
    }
}

fun main() {
    // Deeply nested input recurses deeply; run on a thread with a large stack.
    val worker = Thread(null, ::run, "calc", 1L shl 30)
    worker.start()
    worker.join()
    exitProcess(0)
}
