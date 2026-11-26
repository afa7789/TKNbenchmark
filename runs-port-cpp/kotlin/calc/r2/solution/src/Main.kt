// calc: a 64-bit signed integer expression evaluator.
//
// Reads one expression per line from standard input and prints its value or
// "error". Parsing uses an explicit-stack operator-precedence algorithm so that
// deeply nested input cannot overflow the call stack.

package calc

import java.io.BufferedOutputStream

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

/** Signals a syntax or arithmetic error while evaluating a line. */
private class EvalException : RuntimeException(null, null, false, false)

private fun fail(): Nothing = throw EvalException()

private fun Char.isBlank(): Boolean = this == ' ' || this == '\t'

private fun Char.isAsciiDigit(): Boolean = this in '0'..'9'

/** Growable stack of primitive longs, avoiding boxing on the hot path. */
private class LongStack {
    private var data = LongArray(16)
    var size = 0
        private set

    fun push(value: Long) {
        if (size == data.size) data = data.copyOf(size * 2)
        data[size++] = value
    }

    fun pop(): Long = data[--size]

    fun peek(): Long = data[size - 1]

    fun clear() {
        size = 0
    }
}

class Evaluator {
    private val values = LongStack()
    private val ops = ArrayList<Op>()

    /** Returns the value of [line], or null on any syntax or arithmetic error. */
    fun evaluate(line: CharSequence): Long? = try {
        evaluateOrThrow(line)
    } catch (_: EvalException) {
        null
    } catch (_: ArithmeticException) {
        null
    }

    private fun evaluateOrThrow(line: CharSequence): Long {
        values.clear()
        ops.clear()

        var expectOperand = true
        var i = 0
        val n = line.length

        while (i < n) {
            val c = line[i]
            if (c.isBlank()) {
                i++
                continue
            }
            if (expectOperand) {
                when {
                    c.isAsciiDigit() -> {
                        var value = 0L
                        while (i < n && line[i].isAsciiDigit()) {
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
            } else {
                if (c == ')') {
                    while (ops.isNotEmpty() && ops.last() != Op.LPAREN) reduce()
                    if (ops.isEmpty()) fail() // unbalanced ')'
                    ops.removeLast()
                } else {
                    val op = Op.binary(c) ?: fail()
                    // All binary operators are left-associative.
                    while (ops.isNotEmpty() && ops.last().precedence >= op.precedence) reduce()
                    ops.add(op)
                    expectOperand = true
                }
            }
            i++
        }

        if (expectOperand) fail() // missing operand (or empty)
        while (ops.isNotEmpty()) {
            if (ops.last() == Op.LPAREN) fail() // unbalanced '('
            reduce()
        }
        if (values.size != 1) fail()
        return values.peek()
    }

    /** Applies the operator on top of the stack; throws on arithmetic error. */
    private fun reduce() {
        val op = ops.removeLast()
        val result = if (op == Op.NEG) {
            Math.negateExact(values.pop())
        } else {
            val rhs = values.pop()
            val lhs = values.pop()
            when (op) {
                Op.ADD -> Math.addExact(lhs, rhs)
                Op.SUB -> Math.subtractExact(lhs, rhs)
                Op.MUL -> Math.multiplyExact(lhs, rhs)
                Op.DIV -> if (rhs == 0L) fail() else Math.divideExact(lhs, rhs)
                // The JVM defines Long.MIN_VALUE % -1 as 0, matching the spec.
                Op.REM -> if (rhs == 0L) fail() else lhs % rhs
                Op.NEG, Op.LPAREN -> error("unreachable")
            }
        }
        values.push(result)
    }
}

private fun CharSequence.isBlankLine(): Boolean = all { it.isBlank() }

fun main() {
    // Latin-1 maps every byte to one char, so arbitrary input bytes are handled safely.
    val text = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val evaluator = Evaluator()
    val output = StringBuilder(text.length / 2 + 64)

    var start = 0
    while (start < text.length) {
        var end = text.indexOf('\n', start)
        if (end < 0) end = text.length
        val line = text.subSequence(start, end)
        start = end + 1

        if (line.isBlankLine()) continue
        val value = evaluator.evaluate(line)
        if (value != null) output.append(value) else output.append("error")
        output.append('\n')
    }

    BufferedOutputStream(System.out, 1 shl 16).use {
        it.write(output.toString().toByteArray(Charsets.ISO_8859_1))
    }
}
