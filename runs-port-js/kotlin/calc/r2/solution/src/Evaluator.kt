package calc

/** Signals any condition that makes a line evaluate to `error`. */
class EvalException(message: String) : RuntimeException(message, null, false, false)

private fun fail(message: String): Nothing = throw EvalException(message)

/**
 * Signed 64-bit integer expression evaluator.
 *
 * Uses an iterative operator-precedence (shunting-yard) parser, so arbitrarily
 * deep nesting cannot exhaust the call stack.
 */
object Evaluator {
    // Operator stack entries; binary operators are stored as their character.
    private const val LPAREN = '('
    private const val NEGATE = '~'

    private fun precedence(op: Char): Int = when (op) {
        '+', '-' -> 1
        '*', '/', '%' -> 2
        NEGATE -> 3
        else -> 0
    }

    private fun applyBinary(op: Char, a: Long, b: Long): Long = when (op) {
        '+' -> checked { Math.addExact(a, b) }
        '-' -> checked { Math.subtractExact(a, b) }
        '*' -> checked { Math.multiplyExact(a, b) }
        '/' -> {
            if (b == 0L) fail("division by zero")
            if (a == Long.MIN_VALUE && b == -1L) fail("overflow")
            a / b
        }
        '%' -> {
            if (b == 0L) fail("division by zero")
            a % b // sign follows the dividend; MIN_VALUE % -1 == 0
        }
        else -> error("unknown operator $op")
    }

    private inline fun checked(op: () -> Long): Long =
        try {
            op()
        } catch (_: ArithmeticException) {
            fail("overflow")
        }

    private fun parseLiteral(line: CharSequence, start: Int, end: Int): Long {
        var value = 0L
        for (i in start until end) {
            val digit = line[i] - '0'
            if (value > (Long.MAX_VALUE - digit) / 10) fail("overflow")
            value = value * 10 + digit
        }
        return value
    }

    /**
     * Evaluates one expression.
     *
     * @return the value, or `null` when the line is blank
     * @throws EvalException on syntax error, division by zero or overflow
     */
    fun evaluate(line: CharSequence): Long? {
        val values = LongStack()
        val ops = StringBuilder()
        var expectOperand = true
        var sawToken = false

        fun reduceTop() {
            val op = ops[ops.lastIndex]
            ops.setLength(ops.lastIndex)
            if (op == NEGATE) {
                values.push(checked { Math.negateExact(values.pop()) })
            } else {
                val b = values.pop()
                val a = values.pop()
                values.push(applyBinary(op, a, b))
            }
        }

        val n = line.length
        var i = 0
        while (i < n) {
            val c = line[i]
            if (c == ' ' || c == '\t') {
                i++
                continue
            }
            sawToken = true

            if (expectOperand) {
                when (c) {
                    in '0'..'9' -> {
                        val start = i
                        while (i < n && line[i] in '0'..'9') i++
                        values.push(parseLiteral(line, start, i))
                        expectOperand = false
                        continue
                    }
                    '-' -> ops.append(NEGATE)
                    '(' -> ops.append(LPAREN)
                    else -> fail("expected operand")
                }
                i++
                continue
            }

            when (c) {
                '+', '-', '*', '/', '%' -> {
                    // All binary operators are left-associative.
                    val p = precedence(c)
                    while (ops.isNotEmpty() && precedence(ops.last()) >= p) reduceTop()
                    ops.append(c)
                    expectOperand = true
                }
                ')' -> {
                    while (ops.isNotEmpty() && ops.last() != LPAREN) reduceTop()
                    if (ops.isEmpty()) fail("unbalanced parenthesis")
                    ops.setLength(ops.lastIndex)
                }
                else -> fail("unexpected character")
            }
            i++
        }

        if (!sawToken) return null
        if (expectOperand) fail("missing operand")
        while (ops.isNotEmpty()) {
            if (ops.last() == LPAREN) fail("unbalanced parenthesis")
            reduceTop()
        }
        return values.pop()
    }
}

/** Minimal growable stack of primitive longs. */
private class LongStack {
    private var items = LongArray(16)
    private var size = 0

    fun push(value: Long) {
        if (size == items.size) items = items.copyOf(size * 2)
        items[size++] = value
    }

    fun pop(): Long = items[--size]
}
