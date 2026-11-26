/*
 * Signed 64-bit integer expression evaluator.
 *
 * Grammar:
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *
 * Parsing is iterative (operator-precedence with explicit stacks) so that
 * deeply nested input cannot exhaust the call stack.
 */
package calc

/** Thrown for any syntax, domain, or overflow error. */
class CalcException(message: String) : Exception(message)

private enum class Op(val precedence: Int) {
    ADD(1), SUB(1), MUL(2), DIV(2), REM(2),
    NEG(Int.MAX_VALUE), OPEN(0);

    companion object {
        fun binaryOf(ch: Char): Op? = when (ch) {
            '+' -> ADD
            '-' -> SUB
            '*' -> MUL
            '/' -> DIV
            '%' -> REM
            else -> null
        }
    }
}

private fun Char.isBlankChar(): Boolean = this == ' ' || this == '\t'

private fun fail(message: String): Nothing = throw CalcException(message)

private inline fun checked(block: () -> Long): Long =
    try {
        block()
    } catch (_: ArithmeticException) {
        fail("overflow")
    }

private fun applyBinary(op: Op, a: Long, b: Long): Long = when (op) {
    Op.ADD -> checked { Math.addExact(a, b) }
    Op.SUB -> checked { Math.subtractExact(a, b) }
    Op.MUL -> checked { Math.multiplyExact(a, b) }
    Op.DIV -> {
        if (b == 0L) fail("division by zero")
        if (a == Long.MIN_VALUE && b == -1L) fail("overflow")
        a / b // Truncates toward zero.
    }
    Op.REM -> {
        if (b == 0L) fail("division by zero")
        a % b // Sign follows the dividend; MIN % -1 is 0 on the JVM.
    }
    Op.NEG, Op.OPEN -> error("not a binary operator: $op")
}

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
}

private class Evaluator(private val src: String) {
    private val values = LongStack()
    private val ops = ArrayList<Op>()

    fun run(): Long {
        var expectOperand = true
        var i = 0
        while (i < src.length) {
            val ch = src[i]
            when {
                ch.isBlankChar() -> i++

                ch in '0'..'9' -> {
                    if (!expectOperand) fail("unexpected number")
                    i = readNumber(i)
                    expectOperand = false
                }

                expectOperand -> {
                    when (ch) {
                        '-' -> ops.add(Op.NEG)
                        '(' -> ops.add(Op.OPEN)
                        else -> fail("unexpected '$ch'")
                    }
                    i++
                }

                ch == ')' -> {
                    while (true) {
                        val top = ops.lastOrNull() ?: fail("unmatched ')'")
                        if (top == Op.OPEN) break
                        reduceTop()
                    }
                    ops.removeLast()
                    i++
                }

                else -> {
                    val op = Op.binaryOf(ch) ?: fail("unexpected '$ch'")
                    while (true) {
                        val top = ops.lastOrNull()
                        if (top == null || top == Op.OPEN || top.precedence < op.precedence) break
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
            if (ops.last() == Op.OPEN) fail("unmatched '('")
            reduceTop()
        }
        return values.pop()
    }

    /** Parses the literal starting at [start] and returns the index just past it. */
    private fun readNumber(start: Int): Int {
        var i = start
        var value = 0L
        while (i < src.length && src[i] in '0'..'9') {
            val digit = (src[i] - '0').toLong()
            if (value > (Long.MAX_VALUE - digit) / 10) fail("literal out of range")
            value = value * 10 + digit
            i++
        }
        values.push(value)
        return i
    }

    private fun reduceTop() {
        when (val op = ops.removeLast()) {
            Op.OPEN -> Unit
            Op.NEG -> {
                val v = values.pop()
                values.push(checked { Math.negateExact(v) })
            }
            else -> {
                val b = values.pop()
                val a = values.pop()
                values.push(applyBinary(op, a, b))
            }
        }
    }
}

/** Evaluates one expression. Throws [CalcException] on any error. */
fun evaluate(src: String): Long = Evaluator(src).run()

/** Returns true if the line contains only spaces and tabs. */
fun isBlank(line: String): Boolean = line.all { it.isBlankChar() }

/** Produces the output line for one input line, or null if nothing is printed. */
fun evaluateLine(line: String): String? {
    if (isBlank(line)) return null
    return try {
        evaluate(line).toString()
    } catch (_: CalcException) {
        "error"
    }
}
