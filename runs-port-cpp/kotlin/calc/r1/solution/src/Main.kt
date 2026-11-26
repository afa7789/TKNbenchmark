// calc: a 64-bit signed integer expression evaluator.
//
// Reads one expression per line from standard input and prints its value or
// "error". Parsing uses explicit operator and value stacks (shunting-yard)
// rather than recursion, so arbitrarily deep nesting cannot overflow the stack.

import java.io.BufferedOutputStream
import java.io.PrintStream

private enum class Op(val precedence: Int) {
    ADD(1), SUB(1), MUL(2), DIV(2), MOD(2), NEG(3), LPAREN(0);

    companion object {
        fun binary(c: Char): Op? = when (c) {
            '+' -> ADD
            '-' -> SUB
            '*' -> MUL
            '/' -> DIV
            '%' -> MOD
            else -> null
        }
    }
}

/** Signals an evaluation failure: syntax error, division by zero or overflow. */
private class EvalException : RuntimeException(null, null, false, false)

private fun fail(): Nothing = throw EvalException()

/** Growable stack of primitive longs, avoiding boxing on the hot path. */
private class LongStack {
    private var items = LongArray(16)
    var size = 0
        private set

    fun clear() {
        size = 0
    }

    fun push(value: Long) {
        if (size == items.size) items = items.copyOf(size * 2)
        items[size++] = value
    }

    fun pop(): Long = items[--size]

    var top: Long
        get() = items[size - 1]
        set(value) {
            items[size - 1] = value
        }
}

private fun apply(op: Op, lhs: Long, rhs: Long): Long = try {
    when (op) {
        Op.ADD -> Math.addExact(lhs, rhs)
        Op.SUB -> Math.subtractExact(lhs, rhs)
        Op.MUL -> Math.multiplyExact(lhs, rhs)
        Op.DIV -> if (rhs == 0L) fail() else Math.divideExact(lhs, rhs)
        Op.MOD -> if (rhs == 0L) fail() else lhs % rhs
        Op.NEG, Op.LPAREN -> error("not a binary operator: $op")
    }
} catch (_: ArithmeticException) {
    fail()
}

class Evaluator {
    private val values = LongStack()
    private val ops = ArrayList<Op>()

    /** Returns the value of [line], or `null` on any error. */
    fun evaluate(line: String): Long? = try {
        parse(line)
    } catch (_: EvalException) {
        null
    }

    private fun parse(line: String): Long {
        values.clear()
        ops.clear()
        var expectOperand = true
        var i = 0
        val n = line.length

        while (true) {
            while (i < n && line[i].isBlankChar()) i++
            if (i == n) break
            val c = line[i]

            if (expectOperand) {
                when {
                    c in '0'..'9' -> {
                        var value = 0L
                        while (i < n && line[i] in '0'..'9') {
                            val digit = (line[i] - '0').toLong()
                            if (value > (Long.MAX_VALUE - digit) / 10) fail()
                            value = value * 10 + digit
                            i++
                        }
                        values.push(value)
                        expectOperand = false
                        continue
                    }
                    c == '-' -> ops.add(Op.NEG)
                    c == '(' -> ops.add(Op.LPAREN)
                    else -> fail()
                }
                i++
                continue
            }

            if (c == ')') {
                while (ops.isNotEmpty() && ops.last() != Op.LPAREN) reduce()
                if (ops.isEmpty()) fail()
                ops.removeLast()
            } else {
                val op = Op.binary(c) ?: fail()
                // Left associativity: reduce operators of equal or higher precedence.
                while (ops.isNotEmpty() && ops.last().precedence >= op.precedence) reduce()
                ops.add(op)
                expectOperand = true
            }
            i++
        }

        if (expectOperand) fail()
        while (ops.isNotEmpty()) {
            if (ops.last() == Op.LPAREN) fail()
            reduce()
        }
        return values.top
    }

    /** Applies the operator on top of the stack to its operand(s). */
    private fun reduce() {
        val op = ops.removeLast()
        if (op == Op.NEG) {
            val operand = values.top
            if (operand == Long.MIN_VALUE) fail()
            values.top = -operand
        } else {
            val rhs = values.pop()
            values.top = apply(op, values.top, rhs)
        }
    }
}

private fun Char.isBlankChar(): Boolean = this == ' ' || this == '\t'

private fun String.isBlankLine(): Boolean = all { it.isBlankChar() }

fun main() {
    // Latin-1 maps every byte to one char, so arbitrary input bytes are handled losslessly.
    val text = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val evaluator = Evaluator()
    val output = StringBuilder(text.length)

    var pos = 0
    while (pos < text.length) {
        var end = text.indexOf('\n', pos)
        if (end < 0) end = text.length
        val line = text.substring(pos, end)
        pos = end + 1

        if (line.isBlankLine()) continue
        output.append(evaluator.evaluate(line)?.toString() ?: "error").append('\n')
    }

    PrintStream(BufferedOutputStream(System.out), false, Charsets.ISO_8859_1).use {
        it.print(output)
    }
}
