// calc: 64-bit signed integer expression evaluator (see SPEC.md).
//
// Each input line is evaluated with an iterative operator-precedence parser,
// so arbitrarily deep nesting cannot overflow the call stack.

import java.io.BufferedOutputStream

private enum class Op(val precedence: Int) {
    LParen(0), Add(1), Sub(1), Mul(2), Div(2), Mod(2), Neg(3);

    companion object {
        fun binary(c: Char): Op? = when (c) {
            '+' -> Add
            '-' -> Sub
            '*' -> Mul
            '/' -> Div
            '%' -> Mod
            else -> null
        }
    }
}

/** Thrown internally for any syntax or arithmetic error in a line. */
private class EvalError : RuntimeException(null, null, false, false)

private fun fail(): Nothing = throw EvalError()

private fun Char.isBlank(): Boolean = this == ' ' || this == '\t'

private fun Char.isAsciiDigit(): Boolean = this in '0'..'9'

private fun applyBinary(op: Op, a: Long, b: Long): Long = try {
    when (op) {
        Op.Add -> Math.addExact(a, b)
        Op.Sub -> Math.subtractExact(a, b)
        Op.Mul -> Math.multiplyExact(a, b)
        Op.Div -> if (b == 0L || (a == Long.MIN_VALUE && b == -1L)) fail() else a / b
        Op.Mod -> if (b == 0L) fail() else a % b // JVM: Long.MIN_VALUE % -1 == 0
        else -> fail()
    }
} catch (_: ArithmeticException) {
    fail()
}

/** Growable stack of primitive longs, avoiding boxing on the hot path. */
private class LongStack {
    private var data = LongArray(16)
    var size = 0
        private set

    fun push(v: Long) {
        if (size == data.size) data = data.copyOf(size * 2)
        data[size++] = v
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
    } catch (_: EvalError) {
        null
    }

    private fun evaluateOrThrow(line: CharSequence): Long {
        values.clear()
        ops.clear()

        var expectOperand = true
        var i = 0
        val n = line.length

        while (true) {
            while (i < n && line[i].isBlank()) i++
            if (i == n) break
            val c = line[i]

            if (expectOperand) {
                when {
                    c == '-' -> { ops.add(Op.Neg); i++ }
                    c == '(' -> { ops.add(Op.LParen); i++ }
                    c.isAsciiDigit() -> {
                        i = parseNumber(line, i)
                        expectOperand = false
                    }
                    else -> fail()
                }
            } else {
                val op = Op.binary(c)
                when {
                    c == ')' -> {
                        reduceWhile { it != Op.LParen }
                        if (ops.isEmpty()) fail() // unmatched ')'
                        ops.removeLast()
                        i++
                    }
                    op != null -> {
                        reduceWhile { it.precedence >= op.precedence }
                        ops.add(op)
                        expectOperand = true
                        i++
                    }
                    else -> fail()
                }
            }
        }

        if (expectOperand) fail() // missing operand
        reduceWhile { it != Op.LParen }
        if (ops.isNotEmpty() || values.size != 1) fail() // unmatched '('
        return values.peek()
    }

    /** Parses the literal starting at [start], pushes it, and returns the index after it. */
    private fun parseNumber(line: CharSequence, start: Int): Int {
        var i = start
        var v = 0L
        var overflow = false
        while (i < line.length && line[i].isAsciiDigit()) {
            val d = (line[i] - '0').toLong()
            if (v > (Long.MAX_VALUE - d) / 10) overflow = true else v = v * 10 + d
            i++
        }
        if (overflow) fail()
        values.push(v)
        return i
    }

    private fun reduceOnce() {
        val op = ops.removeLast()
        val result = if (op == Op.Neg) {
            val a = values.pop()
            if (a == Long.MIN_VALUE) fail()
            -a
        } else {
            val b = values.pop()
            val a = values.pop()
            applyBinary(op, a, b)
        }
        values.push(result)
    }

    private inline fun reduceWhile(pred: (Op) -> Boolean) {
        while (ops.isNotEmpty() && pred(ops.last())) reduceOnce()
    }
}

private fun isBlankLine(line: CharSequence): Boolean = line.all { it.isBlank() }

fun main() {
    // Latin-1 maps every byte to one char, so arbitrary bytes are handled losslessly.
    val input = String(System.`in`.readBytes(), Charsets.ISO_8859_1)
    val evaluator = Evaluator()
    val output = StringBuilder(input.length / 2 + 16)

    var start = 0
    while (start < input.length) {
        var end = input.indexOf('\n', start)
        if (end < 0) end = input.length
        val line = input.subSequence(start, end)
        start = end + 1

        if (isBlankLine(line)) continue
        val value = evaluator.evaluate(line)
        if (value != null) output.append(value) else output.append("error")
        output.append('\n')
    }

    BufferedOutputStream(System.out, 1 shl 16).use {
        it.write(output.toString().toByteArray(Charsets.ISO_8859_1))
    }
}
