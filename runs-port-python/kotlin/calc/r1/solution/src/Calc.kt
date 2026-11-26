/**
 * 64-bit signed integer expression evaluator.
 *
 * Reads one expression per line from standard input and prints its value,
 * or `error` for syntax errors, division by zero, and 64-bit overflow.
 */
package calc

import java.io.BufferedOutputStream

/** Raised for any syntax, domain, or overflow error in an expression. */
class CalcException(message: String) : Exception(message, null, false, false)

private fun fail(message: String): Nothing = throw CalcException(message)

private fun Byte.isBlank(): Boolean = this == SPACE || this == TAB

private const val SPACE = ' '.code.toByte()
private const val TAB = '\t'.code.toByte()
private const val NEWLINE = '\n'.code.toByte()

/** Operators held on the shunting-yard stack, with their binding strength. */
private enum class Op(val precedence: Int) {
    ADD(1), SUB(1), MUL(2), DIV(2), REM(2), NEG(3), LPAREN(0);

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

private fun divide(a: Long, b: Long): Long {
    if (b == 0L) fail("division by zero")
    if (a == Long.MIN_VALUE && b == -1L) fail("overflow")
    return a / b
}

private fun remainder(a: Long, b: Long): Long {
    if (b == 0L) fail("division by zero")
    // Truncated remainder always fits, e.g. Long.MIN_VALUE % -1 == 0.
    return a % b
}

private fun applyBinary(op: Op, a: Long, b: Long): Long = try {
    when (op) {
        Op.ADD -> Math.addExact(a, b)
        Op.SUB -> Math.subtractExact(a, b)
        Op.MUL -> Math.multiplyExact(a, b)
        Op.DIV -> divide(a, b)
        Op.REM -> remainder(a, b)
        Op.NEG, Op.LPAREN -> error("not a binary operator: $op")
    }
} catch (_: ArithmeticException) {
    fail("overflow")
}

/**
 * Evaluates expressions using an operator-precedence (shunting-yard) algorithm,
 * so deeply nested input cannot exhaust the call stack. Stacks are reused
 * across lines to avoid per-line allocation.
 */
class Evaluator {
    private var values = LongArray(64)
    private var valueCount = 0
    private val ops = ArrayList<Op>()

    /** Evaluates `line[start, end)` as one expression. */
    fun evaluate(line: ByteArray, start: Int, end: Int): Long {
        valueCount = 0
        ops.clear()

        var stop = end
        while (stop > start && line[stop - 1].isBlank()) stop--

        var expectOperand = true
        var pos = start
        while (pos < stop) {
            val b = line[pos]
            if (b.isBlank()) {
                pos++
                continue
            }
            val c = (b.toInt() and 0xFF).toChar()
            if (expectOperand) {
                when {
                    c in '0'..'9' -> {
                        pos = parseNumber(line, pos, stop)
                        expectOperand = false
                        continue
                    }
                    c == '-' -> ops.add(Op.NEG)
                    c == '(' -> ops.add(Op.LPAREN)
                    else -> fail("expected operand")
                }
            } else if (c == ')') {
                while (ops.isNotEmpty() && ops.last() != Op.LPAREN) reduceTop()
                if (ops.isEmpty()) fail("unbalanced ')'")
                ops.removeLast()
            } else {
                val op = Op.binary(c) ?: fail("expected operator")
                // Left-associative: reduce operators of equal or higher precedence.
                while (ops.isNotEmpty() && ops.last().precedence >= op.precedence) reduceTop()
                ops.add(op)
                expectOperand = true
            }
            pos++
        }

        if (expectOperand) fail("missing operand")
        while (ops.isNotEmpty()) {
            if (ops.last() == Op.LPAREN) fail("unbalanced '('")
            reduceTop()
        }
        return values[0]
    }

    /** Parses a decimal literal starting at [pos], pushes it, and returns the index after it. */
    private fun parseNumber(line: ByteArray, pos: Int, stop: Int): Int {
        var value = 0L
        var i = pos
        while (i < stop) {
            val digit = line[i] - '0'.code.toByte()
            if (digit !in 0..9) break
            if (value > (Long.MAX_VALUE - digit) / 10) fail("literal out of range")
            value = value * 10 + digit
            i++
        }
        push(value)
        return i
    }

    private fun push(value: Long) {
        if (valueCount == values.size) values = values.copyOf(values.size * 2)
        values[valueCount++] = value
    }

    private fun pop(): Long = values[--valueCount]

    private fun reduceTop() {
        val op = ops.removeLast()
        if (op == Op.NEG) {
            val v = pop()
            if (v == Long.MIN_VALUE) fail("overflow")
            push(-v)
        } else {
            val b = pop()
            val a = pop()
            push(applyBinary(op, a, b))
        }
    }
}

private fun isBlankLine(data: ByteArray, start: Int, end: Int): Boolean =
    (start until end).all { data[it].isBlank() }

fun main() {
    val input = System.`in`.readBytes()
    val out = BufferedOutputStream(System.out, 1 shl 16)
    val evaluator = Evaluator()
    val errorBytes = "error\n".toByteArray()

    var lineStart = 0
    while (lineStart < input.size) {
        var lineEnd = lineStart
        while (lineEnd < input.size && input[lineEnd] != NEWLINE) lineEnd++

        if (!isBlankLine(input, lineStart, lineEnd)) {
            try {
                val value = evaluator.evaluate(input, lineStart, lineEnd)
                out.write(value.toString().toByteArray())
                out.write(NEWLINE.toInt())
            } catch (_: CalcException) {
                out.write(errorBytes)
            }
        }
        lineStart = lineEnd + 1
    }
    out.flush()
}
