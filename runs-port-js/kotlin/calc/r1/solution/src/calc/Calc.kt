package calc

/** Raised for any expression that has no 64-bit value: bad syntax, division by zero, or overflow. */
class CalcException(message: String) : Exception(message)

/** Operators held on the shunting-yard operator stack. */
private enum class Op(val precedence: Int) {
    ADD(1), SUB(1), MUL(2), DIV(2), REM(2), NEG(3), LPAREN(0);

    companion object {
        fun binary(ch: Char): Op? = when (ch) {
            '+' -> ADD
            '-' -> SUB
            '*' -> MUL
            '/' -> DIV
            '%' -> REM
            else -> null
        }
    }
}

private fun Char.isAsciiDigit() = this in '0'..'9'

private fun Char.isBlank() = this == ' ' || this == '\t'

private inline fun <T> overflowChecked(block: () -> T): T =
    try {
        block()
    } catch (_: ArithmeticException) {
        throw CalcException("overflow")
    }

private fun applyBinary(op: Op, a: Long, b: Long): Long = when (op) {
    Op.ADD -> overflowChecked { Math.addExact(a, b) }
    Op.SUB -> overflowChecked { Math.subtractExact(a, b) }
    Op.MUL -> overflowChecked { Math.multiplyExact(a, b) }
    Op.DIV -> {
        if (b == 0L) throw CalcException("division by zero")
        // Truncates toward zero; only Long.MIN_VALUE / -1 overflows.
        overflowChecked { Math.divideExact(a, b) }
    }
    Op.REM -> {
        if (b == 0L) throw CalcException("division by zero")
        a % b // sign follows the dividend; never overflows
    }
    Op.NEG, Op.LPAREN -> error("not a binary operator: $op")
}

/** Parses the decimal literal `text[start, end)`, rejecting values above [Long.MAX_VALUE]. */
private fun parseLiteral(text: String, start: Int, end: Int): Long {
    var value = 0L
    for (i in start until end) {
        val digit = text[i] - '0'
        if (value > (Long.MAX_VALUE - digit) / 10) throw CalcException("overflow")
        value = value * 10 + digit
    }
    return value
}

/**
 * Evaluates one expression with an operator-precedence (shunting-yard) parser,
 * so deeply nested input cannot exhaust the call stack.
 *
 * @throws CalcException if the expression is malformed or its value is not representable.
 */
fun evaluate(line: String): Long {
    val values = LongStack()
    val ops = ArrayDeque<Op>()
    var expectOperand = true

    fun reduce() {
        val op = ops.removeLast()
        if (op == Op.NEG) {
            values.push(overflowChecked { Math.negateExact(values.pop()) })
        } else {
            val b = values.pop()
            val a = values.pop()
            values.push(applyBinary(op, a, b))
        }
    }

    val n = line.length
    var i = 0
    while (i < n) {
        val ch = line[i]
        if (ch.isBlank()) {
            i++
            continue
        }
        if (expectOperand) {
            when {
                ch.isAsciiDigit() -> {
                    var j = i + 1
                    while (j < n && line[j].isAsciiDigit()) j++
                    values.push(parseLiteral(line, i, j))
                    i = j
                    expectOperand = false
                    continue
                }
                ch == '-' -> ops.addLast(Op.NEG)
                ch == '(' -> ops.addLast(Op.LPAREN)
                else -> throw CalcException("syntax error")
            }
        } else {
            val op = Op.binary(ch)
            when {
                op != null -> {
                    while (ops.isNotEmpty() && ops.last() != Op.LPAREN && ops.last().precedence >= op.precedence) {
                        reduce()
                    }
                    ops.addLast(op)
                    expectOperand = true
                }
                ch == ')' -> {
                    while (ops.isNotEmpty() && ops.last() != Op.LPAREN) reduce()
                    if (ops.isEmpty()) throw CalcException("unbalanced parentheses")
                    ops.removeLast()
                }
                else -> throw CalcException("syntax error")
            }
        }
        i++
    }

    if (expectOperand) throw CalcException("missing operand")
    while (ops.isNotEmpty()) {
        if (ops.last() == Op.LPAREN) throw CalcException("unbalanced parentheses")
        reduce()
    }
    return values.pop()
}

/** Returns the output line for one input line, or `null` for a blank line. */
fun processLine(line: String): String? {
    if (line.all { it.isBlank() }) return null
    return try {
        evaluate(line).toString()
    } catch (_: CalcException) {
        "error"
    }
}

/** A growable stack of primitive longs, avoiding boxing on the hot path. */
private class LongStack {
    private var items = LongArray(16)
    private var size = 0

    fun push(value: Long) {
        if (size == items.size) items = items.copyOf(size * 2)
        items[size++] = value
    }

    fun pop(): Long {
        check(size > 0) { "pop from empty stack" }
        return items[--size]
    }
}
