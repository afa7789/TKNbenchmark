package calc

import java.io.BufferedOutputStream

/** Raised for any condition that makes a line evaluate to `error`. */
class CalcError(message: String) : Exception(message, null, false, false)

/** Operators held on the operator stack, with their binding strength. */
private enum class StackOp(val precedence: Int) {
    OPEN_PAREN(0),
    ADD(1),
    SUB(1),
    MUL(2),
    DIV(2),
    REM(2),
    NEG(3),
}

private const val SPACE = ' '.code.toByte()
private const val TAB = '\t'.code.toByte()
private const val NEWLINE = '\n'.code.toByte()

private fun isBlank(b: Byte): Boolean = b == SPACE || b == TAB
private fun isDigit(b: Byte): Boolean = b in '0'.code..'9'.code

private fun binaryOpFor(b: Byte): StackOp? = when (b.toInt().toChar()) {
    '+' -> StackOp.ADD
    '-' -> StackOp.SUB
    '*' -> StackOp.MUL
    '/' -> StackOp.DIV
    '%' -> StackOp.REM
    else -> null
}

private inline fun <T> checked(block: () -> T): T =
    try {
        block()
    } catch (_: ArithmeticException) {
        throw CalcError("overflow")
    }

private fun applyBinary(op: StackOp, a: Long, b: Long): Long = when (op) {
    StackOp.ADD -> checked { Math.addExact(a, b) }
    StackOp.SUB -> checked { Math.subtractExact(a, b) }
    StackOp.MUL -> checked { Math.multiplyExact(a, b) }
    StackOp.DIV -> {
        if (b == 0L) throw CalcError("division by zero")
        if (a == Long.MIN_VALUE && b == -1L) throw CalcError("overflow")
        a / b // truncates toward zero
    }
    StackOp.REM -> {
        if (b == 0L) throw CalcError("division by zero")
        a % b // sign follows the dividend; MIN % -1 is 0
    }
    StackOp.NEG, StackOp.OPEN_PAREN -> throw IllegalArgumentException("not a binary operator: $op")
}

/** A growable stack of primitive longs. */
private class LongStack {
    private var items = LongArray(16)
    var size = 0
        private set

    fun push(value: Long) {
        if (size == items.size) items = items.copyOf(size * 2)
        items[size++] = value
    }

    fun pop(): Long {
        check(size > 0) { "value stack underflow" }
        return items[--size]
    }

    fun clear() {
        size = 0
    }
}

/**
 * Evaluates expressions using an operator-precedence (shunting-yard) parser
 * with explicit stacks, so deeply nested input cannot overflow the call stack.
 * Instances reuse their stacks between calls and are not thread-safe.
 */
class Evaluator {
    private val values = LongStack()
    private val ops = ArrayList<StackOp>()

    /** Evaluates `input[start until end]`, throwing [CalcError] on any error. */
    fun evaluate(input: ByteArray, start: Int, end: Int): Long {
        values.clear()
        ops.clear()
        var expectOperand = true
        var i = start
        while (i < end) {
            val b = input[i]
            when {
                isBlank(b) -> i++
                expectOperand -> {
                    if (isDigit(b)) {
                        i = parseNumber(input, i, end)
                        expectOperand = false
                    } else {
                        ops += when (b.toInt().toChar()) {
                            '-' -> StackOp.NEG
                            '(' -> StackOp.OPEN_PAREN
                            else -> throw CalcError("syntax")
                        }
                        i++
                    }
                }
                b == ')'.code.toByte() -> {
                    while (ops.isNotEmpty() && ops.last() != StackOp.OPEN_PAREN) reduceTop()
                    if (ops.isEmpty()) throw CalcError("unbalanced")
                    ops.removeLast()
                    i++
                }
                else -> {
                    val op = binaryOpFor(b) ?: throw CalcError("syntax")
                    while (ops.isNotEmpty() && ops.last().precedence >= op.precedence) reduceTop()
                    ops += op
                    expectOperand = true
                    i++
                }
            }
        }

        if (expectOperand) throw CalcError("missing operand")
        while (ops.isNotEmpty()) {
            if (ops.last() == StackOp.OPEN_PAREN) throw CalcError("unbalanced")
            reduceTop()
        }
        return values.pop()
    }

    /** Pushes the literal starting at [start] and returns the index just past it. */
    private fun parseNumber(input: ByteArray, start: Int, end: Int): Int {
        var value = 0L
        var j = start
        while (j < end && isDigit(input[j])) {
            val digit = (input[j] - '0'.code.toByte()).toLong()
            value = checked { Math.addExact(Math.multiplyExact(value, 10L), digit) }
            j++
        }
        values.push(value)
        return j
    }

    private fun reduceTop() {
        when (val op = ops.removeLast()) {
            StackOp.OPEN_PAREN -> error("unexpected parenthesis on reduce")
            StackOp.NEG -> {
                val v = values.pop()
                values.push(checked { Math.negateExact(v) })
            }
            else -> {
                val rhs = values.pop()
                val lhs = values.pop()
                values.push(applyBinary(op, lhs, rhs))
            }
        }
    }
}

private fun isBlankRange(input: ByteArray, start: Int, end: Int): Boolean =
    (start until end).all { isBlank(input[it]) }

fun main() {
    val input = System.`in`.readBytes()
    val evaluator = Evaluator()
    val out = StringBuilder()

    var lineStart = 0
    while (lineStart < input.size) {
        var lineEnd = lineStart
        while (lineEnd < input.size && input[lineEnd] != NEWLINE) lineEnd++
        if (!isBlankRange(input, lineStart, lineEnd)) {
            try {
                out.append(evaluator.evaluate(input, lineStart, lineEnd))
            } catch (_: CalcError) {
                out.append("error")
            }
            out.append('\n')
        }
        lineStart = lineEnd + 1
    }

    BufferedOutputStream(System.out, 1 shl 16).use { it.write(out.toString().toByteArray(Charsets.ISO_8859_1)) }
}
