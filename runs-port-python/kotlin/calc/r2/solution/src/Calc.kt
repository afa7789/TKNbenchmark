/**
 * Line-oriented 64-bit signed integer expression evaluator.
 *
 * Reads one expression per line from stdin and prints its value or `error`.
 * Parsing uses explicit operator/value stacks (shunting-yard) so that deeply
 * nested input cannot exhaust the call stack.
 */
package calc

import java.io.BufferedOutputStream

/** Raised for any syntax, domain, or overflow error in an expression. */
class CalcException(message: String) : Exception(message, null, false, false)

private enum class Op(val precedence: Int) {
    ADD(1), SUB(1), MUL(2), DIV(2), REM(2), NEG(3), LPAREN(0);

    companion object {
        fun binary(byte: Int): Op? = when (byte) {
            '+'.code -> ADD
            '-'.code -> SUB
            '*'.code -> MUL
            '/'.code -> DIV
            '%'.code -> REM
            else -> null
        }
    }
}

private fun isBlank(byte: Int) = byte == ' '.code || byte == '\t'.code

private fun isDigit(byte: Int) = byte in '0'.code..'9'.code

/** Growable stack of primitive longs, avoiding boxing on the hot path. */
private class LongStack {
    private var items = LongArray(16)
    var size = 0
        private set

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

    fun clear() {
        size = 0
    }
}

/** Evaluates expressions; reuses its stacks between calls, so it is not thread-safe. */
class Evaluator {
    private val values = LongStack()
    private val ops = ArrayList<Op>()

    /** Evaluates `line[start, end)`, throwing [CalcException] on any failure. */
    fun evaluate(line: ByteArray, start: Int = 0, end: Int = line.size): Long {
        values.clear()
        ops.clear()
        var expectOperand = true
        var pos = start

        while (pos < end) {
            val c = line[pos].toInt() and 0xFF
            when {
                isBlank(c) -> pos++

                isDigit(c) -> {
                    if (!expectOperand) throw CalcException("unexpected number")
                    var value = 0L
                    while (pos < end && isDigit(line[pos].toInt())) {
                        val digit = line[pos].toInt() - '0'.code
                        if (value > (Long.MAX_VALUE - digit) / 10) throw CalcException("literal overflow")
                        value = value * 10 + digit
                        pos++
                    }
                    values.push(value)
                    expectOperand = false
                }

                expectOperand -> {
                    when (c) {
                        '-'.code -> ops.add(Op.NEG)
                        '('.code -> ops.add(Op.LPAREN)
                        else -> throw CalcException("unexpected character")
                    }
                    pos++
                }

                c == ')'.code -> {
                    while (ops.isNotEmpty() && ops.last() != Op.LPAREN) apply(ops.removeLast())
                    if (ops.isEmpty()) throw CalcException("unbalanced ')'")
                    ops.removeLast()
                    pos++
                }

                else -> {
                    val op = Op.binary(c) ?: throw CalcException("unexpected character")
                    while (ops.isNotEmpty() && ops.last() != Op.LPAREN && ops.last().precedence >= op.precedence) {
                        apply(ops.removeLast())
                    }
                    ops.add(op)
                    expectOperand = true
                    pos++
                }
            }
        }

        if (expectOperand) throw CalcException("missing operand")
        while (ops.isNotEmpty()) {
            val op = ops.removeLast()
            if (op == Op.LPAREN) throw CalcException("unbalanced '('")
            apply(op)
        }
        return values.top
    }

    private fun apply(op: Op) {
        if (op == Op.NEG) {
            values.top = Math.negateExact(values.top)
            return
        }
        val b = values.pop()
        val a = values.top
        values.top = when (op) {
            Op.ADD -> Math.addExact(a, b)
            Op.SUB -> Math.subtractExact(a, b)
            Op.MUL -> Math.multiplyExact(a, b)
            Op.DIV -> {
                if (b == 0L) throw CalcException("division by zero")
                Math.divideExact(a, b)
            }
            // Sign follows the dividend; Long.MIN_VALUE % -1 is 0, never an overflow.
            Op.REM -> {
                if (b == 0L) throw CalcException("division by zero")
                a % b
            }
            Op.NEG, Op.LPAREN -> error("not a binary operator: $op")
        }
    }

    /** Returns the printed result for one line: its value or `error`. */
    fun render(line: ByteArray, start: Int, end: Int): String = try {
        evaluate(line, start, end).toString()
    } catch (_: CalcException) {
        "error"
    } catch (_: ArithmeticException) {
        "error"
    }
}

fun main() {
    val data = System.`in`.readBytes()
    val evaluator = Evaluator()
    val out = StringBuilder()
    var start = 0
    while (start <= data.size) {
        var end = data.indexOf('\n'.code.toByte(), start)
        if (end < 0) end = data.size
        val blank = (start until end).all { isBlank(data[it].toInt()) }
        if (!blank) out.append(evaluator.render(data, start, end)).append('\n')
        start = end + 1
    }
    BufferedOutputStream(System.out, 1 shl 16).use { it.write(out.toString().toByteArray(Charsets.US_ASCII)) }
}

private fun ByteArray.indexOf(byte: Byte, from: Int): Int {
    for (i in from until size) if (this[i] == byte) return i
    return -1
}
