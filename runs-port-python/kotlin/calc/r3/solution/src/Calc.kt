/**
 * calc: evaluate 64-bit signed integer expressions, one per input line.
 *
 * Each non-blank line of standard input is parsed and evaluated; its value,
 * or `error`, is written to standard output.
 */
package calc

import java.io.BufferedWriter
import java.io.OutputStreamWriter

/** Raised for any syntax, range, or arithmetic error in an expression. */
class CalcException(message: String) : RuntimeException(message, null, false, false)

private fun fail(message: String): Nothing = throw CalcException(message)

/** Operators held on the parser's operator stack. */
private enum class Op(val precedence: Int) {
    ADD(1), SUB(1), MUL(2), DIV(2), REM(2),
    NEGATE(3),
    LPAREN(0);

    companion object {
        fun binary(c: Char): Op? = when (c) {
            '+' -> ADD
            '-' -> SUB
            '*' -> MUL
            '/' -> DIV
            '%' -> REM
            else -> null
        }
    }
}

private fun quotient(a: Long, b: Long): Long {
    if (b == 0L) fail("division by zero")
    if (a == Long.MIN_VALUE && b == -1L) fail("overflow")
    return a / b
}

private fun remainder(a: Long, b: Long): Long {
    if (b == 0L) fail("division by zero")
    // Remainder of truncating division; always representable (MIN % -1 == 0).
    return a % b
}

private fun applyBinary(op: Op, a: Long, b: Long): Long = try {
    when (op) {
        Op.ADD -> Math.addExact(a, b)
        Op.SUB -> Math.subtractExact(a, b)
        Op.MUL -> Math.multiplyExact(a, b)
        Op.DIV -> quotient(a, b)
        Op.REM -> remainder(a, b)
        Op.NEGATE, Op.LPAREN -> error("not a binary operator: $op")
    }
} catch (_: ArithmeticException) {
    fail("overflow")
}

private fun negate(value: Long): Long {
    if (value == Long.MIN_VALUE) fail("overflow")
    return -value
}

private fun isBlank(c: Char): Boolean = c == ' ' || c == '\t'

/** Parses the decimal literal `line[start, end)`, rejecting values above [Long.MAX_VALUE]. */
private fun parseLiteral(line: String, start: Int, end: Int): Long {
    var value = 0L
    for (i in start until end) {
        val digit = line[i] - '0'
        if (value > (Long.MAX_VALUE - digit) / 10) fail("literal out of range")
        value = value * 10 + digit
    }
    return value
}

/**
 * Evaluates a single expression, throwing [CalcException] if it is invalid.
 *
 * Uses an iterative operator-precedence (shunting-yard) parser so deeply
 * nested input cannot exhaust the call stack.
 */
fun evaluate(line: String): Long {
    val values = LongStack()
    val ops = ArrayList<Op>()

    fun reduceTop() {
        val op = ops.removeLast()
        if (op == Op.NEGATE) {
            values.push(negate(values.pop()))
        } else {
            val b = values.pop()
            val a = values.pop()
            values.push(applyBinary(op, a, b))
        }
    }

    var expectOperand = true
    var i = 0
    val n = line.length
    while (i < n) {
        val c = line[i]
        when {
            isBlank(c) -> i++

            expectOperand -> when {
                c in '0'..'9' -> {
                    val start = i
                    while (i < n && line[i] in '0'..'9') i++
                    values.push(parseLiteral(line, start, i))
                    expectOperand = false
                }
                c == '-' -> { ops.add(Op.NEGATE); i++ }
                c == '(' -> { ops.add(Op.LPAREN); i++ }
                else -> fail("unexpected character '$c'")
            }

            c == ')' -> {
                while (ops.isNotEmpty() && ops.last() != Op.LPAREN) reduceTop()
                if (ops.isEmpty()) fail("unbalanced ')'")
                ops.removeLast()
                i++
            }

            else -> {
                val op = Op.binary(c) ?: fail("unexpected character '$c'")
                // Left-associative: reduce everything of equal or higher binding
                // (unary minus always qualifies) before pushing this operator.
                while (ops.isNotEmpty() && ops.last() != Op.LPAREN && ops.last().precedence >= op.precedence) {
                    reduceTop()
                }
                ops.add(op)
                expectOperand = true
                i++
            }
        }
    }

    if (expectOperand) fail("missing operand")
    while (ops.isNotEmpty()) {
        if (ops.last() == Op.LPAREN) fail("unbalanced '('")
        reduceTop()
    }
    return values.pop()
}

/** A minimal growable stack of primitive longs, avoiding boxing on the hot path. */
private class LongStack {
    private var items = LongArray(16)
    private var size = 0

    fun push(value: Long) {
        if (size == items.size) items = items.copyOf(size * 2)
        items[size++] = value
    }

    fun pop(): Long {
        check(size > 0) { "value stack underflow" }
        return items[--size]
    }
}

/** Returns the output line for an expression, or `null` if the line is blank. */
fun process(line: String): String? {
    if (line.all(::isBlank)) return null
    return try {
        evaluate(line).toString()
    } catch (_: CalcException) {
        "error"
    }
}

fun main() {
    // Latin-1 maps every byte to one character, so arbitrary bytes are
    // accepted and simply rejected as invalid tokens.
    val text = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val lines = text.split('\n').let { if (it.last().isEmpty()) it.dropLast(1) else it }
    BufferedWriter(OutputStreamWriter(System.out, Charsets.ISO_8859_1), 1 shl 16).use { out ->
        for (line in lines) {
            val result = process(line) ?: continue
            out.write(result)
            out.write('\n'.code)
        }
    }
}
