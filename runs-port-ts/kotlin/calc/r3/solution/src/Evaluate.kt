/**
 * Evaluator for signed 64-bit integer arithmetic expressions.
 *
 * Grammar:
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *
 * Parsing is iterative (operator precedence with explicit stacks) so that
 * deeply nested input cannot overflow the call stack.
 */
package calc

/** Thrown for any syntax, division-by-zero, or overflow failure. */
class EvalException(message: String) : RuntimeException(message, null, false, false)

private enum class Op(val precedence: Int) {
    ADD(1), SUBTRACT(1), MULTIPLY(2), DIVIDE(2), REMAINDER(2), NEGATE(3), OPEN(0);

    companion object {
        fun binary(ch: Char): Op? = when (ch) {
            '+' -> ADD
            '-' -> SUBTRACT
            '*' -> MULTIPLY
            '/' -> DIVIDE
            '%' -> REMAINDER
            else -> null
        }
    }
}

private inline fun <T> checked(block: () -> T): T =
    try {
        block()
    } catch (_: ArithmeticException) {
        throw EvalException("overflow")
    }

private fun applyBinary(op: Op, a: Long, b: Long): Long = when (op) {
    Op.ADD -> checked { Math.addExact(a, b) }
    Op.SUBTRACT -> checked { Math.subtractExact(a, b) }
    Op.MULTIPLY -> checked { Math.multiplyExact(a, b) }
    Op.DIVIDE -> {
        if (b == 0L) throw EvalException("division by zero")
        if (a == Long.MIN_VALUE && b == -1L) throw EvalException("overflow")
        a / b // Truncates toward zero.
    }
    Op.REMAINDER -> {
        if (b == 0L) throw EvalException("division by zero")
        a % b // Sign follows the dividend; Long.MIN_VALUE % -1 is 0.
    }
    Op.NEGATE, Op.OPEN -> error("not a binary operator: $op")
}

/** Growable stack of primitive longs, avoiding boxing on the hot path. */
private class LongStack {
    private var items = LongArray(16)
    var size = 0
        private set

    fun push(value: Long) {
        if (size == items.size) items = items.copyOf(size * 2)
        items[size++] = value
    }

    fun pop(): Long {
        if (size == 0) throw EvalException("malformed expression")
        return items[--size]
    }
}

private class Machine {
    private val values = LongStack()
    private val ops = ArrayList<Op>()

    fun pushValue(value: Long) = values.push(value)

    fun pushOpen() {
        ops.add(Op.OPEN)
    }

    fun pushNegate() {
        ops.add(Op.NEGATE)
    }

    /** Reduces pending operators that bind at least as tightly, then pushes [op]. */
    fun pushBinary(op: Op) {
        while (true) {
            val top = ops.lastOrNull()
            if (top == null || top == Op.OPEN || top.precedence < op.precedence) break
            reduceTop()
        }
        ops.add(op)
    }

    /** Reduces up to and including the matching '('. */
    fun close() {
        while (true) {
            when (ops.lastOrNull()) {
                null -> throw EvalException("unbalanced parenthesis")
                Op.OPEN -> {
                    ops.removeAt(ops.lastIndex)
                    return
                }
                else -> reduceTop()
            }
        }
    }

    fun finish(): Long {
        while (ops.isNotEmpty()) {
            if (ops.last() == Op.OPEN) throw EvalException("unbalanced parenthesis")
            reduceTop()
        }
        val result = values.pop()
        if (values.size > 0) throw EvalException("malformed expression")
        return result
    }

    private fun reduceTop() {
        val op = ops.removeAt(ops.lastIndex)
        if (op == Op.NEGATE) {
            values.push(checked { Math.negateExact(values.pop()) })
            return
        }
        val b = values.pop()
        val a = values.pop()
        values.push(applyBinary(op, a, b))
    }
}

private fun Char.isBlankChar(): Boolean = this == ' ' || this == '\t'

/** Returns true when the line contains only spaces and tabs. */
fun isBlankLine(line: CharSequence): Boolean = line.all { it.isBlankChar() }

/** Parses a run of decimal digits, rejecting values above [Long.MAX_VALUE]. */
private fun parseLiteral(source: CharSequence, start: Int, end: Int): Long {
    var value = 0L
    for (i in start until end) {
        val digit = source[i] - '0'
        if (value > (Long.MAX_VALUE - digit) / 10) throw EvalException("literal overflow")
        value = value * 10 + digit
    }
    return value
}

/** Evaluates one expression, throwing [EvalException] on failure. */
fun evaluate(source: CharSequence): Long {
    val machine = Machine()
    // true: the next token must start an operand; false: an operator or ')'.
    var expectOperand = true
    var i = 0
    val n = source.length

    while (i < n) {
        val ch = source[i]
        when {
            ch.isBlankChar() -> i++

            ch in '0'..'9' -> {
                if (!expectOperand) throw EvalException("unexpected number")
                val start = i
                while (i < n && source[i] in '0'..'9') i++
                machine.pushValue(parseLiteral(source, start, i))
                expectOperand = false
            }

            expectOperand -> {
                i++
                when (ch) {
                    '-' -> machine.pushNegate()
                    '(' -> machine.pushOpen()
                    else -> throw EvalException("unexpected '$ch'")
                }
            }

            else -> {
                i++
                if (ch == ')') {
                    machine.close()
                } else {
                    val op = Op.binary(ch) ?: throw EvalException("unexpected '$ch'")
                    machine.pushBinary(op)
                    expectOperand = true
                }
            }
        }
    }

    if (expectOperand) throw EvalException("missing operand")
    return machine.finish()
}
