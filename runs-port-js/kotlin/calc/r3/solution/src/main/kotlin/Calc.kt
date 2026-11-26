// 64-bit signed integer expression evaluator. Reads expressions from stdin,
// one per line, and prints each value or `error`.
//
// The parser is an iterative operator-precedence (shunting-yard) evaluator so
// that arbitrarily deep nesting cannot overflow the call stack.

package calc

import java.io.BufferedOutputStream

/** Raised for any syntax, division-by-zero or overflow error; carries no stack trace. */
private class CalcError : RuntimeException(null, null, false, false)

private fun fail(): Nothing = throw CalcError()

/** Operators kept on the operator stack, with their binding strength. */
private enum class Op(val precedence: Int) {
    LPAREN(0),
    ADD(1),
    SUB(1),
    MUL(2),
    DIV(2),
    REM(2),
    NEG(3);

    fun apply(a: Long, b: Long): Long = try {
        when (this) {
            ADD -> Math.addExact(a, b)
            SUB -> Math.subtractExact(a, b)
            MUL -> Math.multiplyExact(a, b)
            DIV -> if (b == 0L) fail() else Math.divideExact(a, b)
            REM -> if (b == 0L) fail() else a % b
            LPAREN, NEG -> error("$this is not a binary operator")
        }
    } catch (_: ArithmeticException) {
        fail()
    }

    companion object {
        fun binaryOf(c: Char): Op? = when (c) {
            '+' -> ADD
            '-' -> SUB
            '*' -> MUL
            '/' -> DIV
            '%' -> REM
            else -> null
        }
    }
}

/** Minimal growable stack of primitive longs, avoiding boxing on the hot path. */
private class LongStack {
    private var items = LongArray(16)
    var size = 0
        private set

    fun push(v: Long) {
        if (size == items.size) items = items.copyOf(size * 2)
        items[size++] = v
    }

    fun pop(): Long = items[--size]
}

private fun Char.isAsciiDigit() = this in '0'..'9'

private fun Char.isBlank() = this == ' ' || this == '\t'

/** Parses a run of ASCII digits as a non-negative Long, failing on overflow. */
private fun parseLiteral(line: String, start: Int, end: Int): Long {
    var value = 0L
    for (i in start until end) {
        val digit = (line[i] - '0').toLong()
        if (value > (Long.MAX_VALUE - digit) / 10) fail()
        value = value * 10 + digit
    }
    return value
}

/** Evaluates one expression line, throwing [CalcError] on any error. */
private fun evaluate(line: String): Long {
    val values = LongStack()
    val ops = ArrayList<Op>()
    var expectOperand = true

    fun reduceTop() {
        val op = ops.removeLast()
        if (op == Op.NEG) {
            val v = values.pop()
            if (v == Long.MIN_VALUE) fail()
            values.push(-v)
        } else {
            val b = values.pop()
            val a = values.pop()
            values.push(op.apply(a, b))
        }
    }

    val n = line.length
    var i = 0
    while (i < n) {
        val c = line[i]
        when {
            c.isBlank() -> i++

            expectOperand -> {
                when {
                    c.isAsciiDigit() -> {
                        var j = i + 1
                        while (j < n && line[j].isAsciiDigit()) j++
                        values.push(parseLiteral(line, i, j))
                        i = j
                        expectOperand = false
                        continue
                    }
                    c == '-' -> ops.add(Op.NEG)
                    c == '(' -> ops.add(Op.LPAREN)
                    else -> fail()
                }
                i++
            }

            c == ')' -> {
                while (ops.isNotEmpty() && ops.last() != Op.LPAREN) reduceTop()
                if (ops.isEmpty()) fail()
                ops.removeLast()
                i++
            }

            else -> {
                val op = Op.binaryOf(c) ?: fail()
                while (ops.isNotEmpty() && ops.last().precedence >= op.precedence) reduceTop()
                ops.add(op)
                expectOperand = true
                i++
            }
        }
    }

    if (expectOperand) fail()
    while (ops.isNotEmpty()) {
        if (ops.last() == Op.LPAREN) fail()
        reduceTop()
    }
    return values.pop()
}

fun main() {
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val out = StringBuilder()
    var start = 0
    while (start < input.length) {
        val newline = input.indexOf('\n', start)
        val end = if (newline < 0) input.length else newline
        val line = input.substring(start, end)
        start = end + 1
        if (line.all { it.isBlank() }) continue
        val result = try {
            evaluate(line).toString()
        } catch (_: CalcError) {
            "error"
        }
        out.append(result).append('\n')
    }
    BufferedOutputStream(System.out).use { it.write(out.toString().toByteArray(Charsets.ISO_8859_1)) }
}
