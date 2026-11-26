/**
 * Line-oriented evaluator for signed 64-bit integer expressions.
 *
 * Grammar:
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * ```
 */
package calc

import java.io.BufferedWriter
import java.io.InputStream
import java.io.OutputStreamWriter
import java.io.Writer
import kotlin.system.exitProcess

/** Signals that the current line cannot be evaluated. */
class EvalException(message: String) : Exception(message, null, false, false)

private fun fail(message: String): Nothing = throw EvalException(message)

// ---------------------------------------------------------------------------
// Lexer

sealed interface Token {
    data class Number(val value: Long) : Token
    data class Symbol(val char: Char) : Token
}

private const val OPERATORS = "+-*/%()"

private fun Char.isBlank(): Boolean = this == ' ' || this == '\t'

private fun Char.isAsciiDigit(): Boolean = this in '0'..'9'

/** Splits a line into number literals and operator/parenthesis symbols. */
fun tokenize(line: String): List<Token> {
    val tokens = ArrayList<Token>()
    var i = 0
    while (i < line.length) {
        val c = line[i]
        when {
            c.isBlank() -> i++
            c in OPERATORS -> {
                tokens += Token.Symbol(c)
                i++
            }
            c.isAsciiDigit() -> {
                var end = i + 1
                while (end < line.length && line[end].isAsciiDigit()) end++
                val value = line.substring(i, end).toLongOrNull() ?: fail("literal out of range")
                tokens += Token.Number(value)
                i = end
            }
            else -> fail("unexpected character '$c'")
        }
    }
    return tokens
}

// ---------------------------------------------------------------------------
// Checked 64-bit arithmetic

private inline fun checked(block: () -> Long): Long =
    try {
        block()
    } catch (_: ArithmeticException) {
        fail("overflow")
    }

private fun applyOperator(op: Char, a: Long, b: Long): Long = when (op) {
    '+' -> checked { Math.addExact(a, b) }
    '-' -> checked { Math.subtractExact(a, b) }
    '*' -> checked { Math.multiplyExact(a, b) }
    '/' -> when {
        b == 0L -> fail("division by zero")
        a == Long.MIN_VALUE && b == -1L -> fail("overflow")
        else -> a / b
    }
    '%' -> if (b == 0L) fail("division by zero") else a % b
    else -> error("unknown operator $op")
}

private fun negate(a: Long): Long = checked { Math.negateExact(a) }

// ---------------------------------------------------------------------------
// Recursive-descent evaluator

private class Parser(private val tokens: List<Token>) {
    private var pos = 0

    private fun peekSymbol(): Char? = (tokens.getOrNull(pos) as? Token.Symbol)?.char

    fun parseAll(): Long {
        val value = parseExpr()
        if (pos < tokens.size) fail("unexpected token ${tokens[pos]}")
        return value
    }

    private fun parseExpr(): Long = parseLeftAssoc("+-", ::parseTerm)

    private fun parseTerm(): Long = parseLeftAssoc("*/%", ::parseUnary)

    /** Parses `operand (op operand)*` for the operators in [ops], folding left-associatively. */
    private inline fun parseLeftAssoc(ops: String, parseOperand: () -> Long): Long {
        var acc = parseOperand()
        while (true) {
            val op = peekSymbol()?.takeIf { it in ops } ?: return acc
            pos++
            acc = applyOperator(op, acc, parseOperand())
        }
    }

    /** Consumes runs of minus signs iteratively so chains like `-----1` use no stack depth. */
    private fun parseUnary(): Long {
        var negations = 0
        while (peekSymbol() == '-') {
            negations++
            pos++
        }
        var value = parsePrimary()
        repeat(negations) { value = negate(value) }
        return value
    }

    private fun parsePrimary(): Long = when (val token = tokens.getOrNull(pos)) {
        is Token.Number -> {
            pos++
            token.value
        }
        Token.Symbol('(') -> {
            pos++
            val value = parseExpr()
            if (peekSymbol() != ')') fail("expected ')'")
            pos++
            value
        }
        null -> fail("unexpected end of input")
        else -> fail("unexpected token $token")
    }
}

/** Evaluates an expression line, throwing [EvalException] when it is invalid. */
fun evaluate(line: String): Long = Parser(tokenize(line)).parseAll()

/** Returns the output for one input line: its value, `"error"`, or `null` for a blank line. */
fun evalLine(line: String): String? {
    if (line.all { it.isBlank() }) return null
    return try {
        evaluate(line).toString()
    } catch (_: EvalException) {
        "error"
    } catch (_: StackOverflowError) {
        "error"
    }
}

// ---------------------------------------------------------------------------
// Entry point

/**
 * Splits input on `\n` only; a carriage return stays part of its line and is
 * therefore reported as a syntax error. A trailing unterminated line is kept.
 */
private fun InputStream.lines(): Sequence<String> = sequence {
    val reader = this@lines.bufferedReader(Charsets.ISO_8859_1)
    val line = StringBuilder()
    while (true) {
        val c = reader.read()
        when (c) {
            -1 -> {
                if (line.isNotEmpty()) yield(line.toString())
                return@sequence
            }
            '\n'.code -> {
                yield(line.toString())
                line.setLength(0)
            }
            else -> line.append(c.toChar())
        }
    }
}

private fun run(input: InputStream, out: Writer) {
    for (line in input.lines()) {
        val result = evalLine(line) ?: continue
        out.write(result)
        out.write("\n")
    }
    out.flush()
}

private const val PARSER_STACK_BYTES = 1L shl 30

fun main() {
    val out = BufferedWriter(OutputStreamWriter(System.out, Charsets.ISO_8859_1), 1 shl 16)
    // Deeply nested parentheses recurse; give the parser a roomy stack.
    val worker = Thread(null, { run(System.`in`.buffered(1 shl 16), out) }, "calc", PARSER_STACK_BYTES)
    worker.start()
    worker.join()
    exitProcess(0)
}
