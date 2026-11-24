package calc

import java.io.BufferedOutputStream
import java.io.PrintStream

/** Raised for any condition that makes a line evaluate to `error`. */
private class CalcException : RuntimeException(null, null, false, false)

/**
 * Iterative (shunting-yard) evaluator for the calc grammar, so arbitrarily deep
 * nesting cannot overflow the call stack. Instances are reusable across lines.
 */
class Evaluator {
    private var values = LongArray(64)
    private var valueCount = 0
    private var ops = CharArray(64)
    private var opCount = 0

    /** Returns the value of [line], or null if it is erroneous. */
    fun evaluate(line: CharSequence): Long? = try {
        run(line)
    } catch (_: CalcException) {
        null
    }

    private fun run(line: CharSequence): Long {
        valueCount = 0
        opCount = 0
        var expectOperand = true
        var i = 0
        val n = line.length
        while (i < n) {
            val c = line[i]
            when {
                c == ' ' || c == '\t' -> i++
                expectOperand -> when (c) {
                    '-' -> { pushOp(UNARY_MINUS); i++ }
                    '(' -> { pushOp('('); i++ }
                    in '0'..'9' -> {
                        var value = 0L
                        while (i < n && line[i] in '0'..'9') {
                            val digit = line[i] - '0'
                            if (value > (Long.MAX_VALUE - digit) / 10) fail()
                            value = value * 10 + digit
                            i++
                        }
                        pushValue(value)
                        expectOperand = false
                    }
                    else -> fail()
                }
                else -> when (c) {
                    '+', '-', '*', '/', '%' -> {
                        val prec = precedence(c)
                        while (opCount > 0 && ops[opCount - 1] != '(' && precedence(ops[opCount - 1]) >= prec) {
                            reduce()
                        }
                        pushOp(c)
                        expectOperand = true
                        i++
                    }
                    ')' -> {
                        while (opCount > 0 && ops[opCount - 1] != '(') reduce()
                        if (opCount == 0) fail()
                        opCount--
                        i++
                    }
                    else -> fail()
                }
            }
        }
        if (expectOperand) fail()
        while (opCount > 0) {
            if (ops[opCount - 1] == '(') fail()
            reduce()
        }
        return values[0]
    }

    private fun reduce() {
        val op = ops[--opCount]
        if (op == UNARY_MINUS) {
            val a = values[valueCount - 1]
            if (a == Long.MIN_VALUE) fail()
            values[valueCount - 1] = -a
            return
        }
        val b = values[--valueCount]
        val a = values[valueCount - 1]
        values[valueCount - 1] = apply(op, a, b)
    }

    private fun apply(op: Char, a: Long, b: Long): Long = try {
        when (op) {
            '+' -> Math.addExact(a, b)
            '-' -> Math.subtractExact(a, b)
            '*' -> Math.multiplyExact(a, b)
            '/' -> {
                if (b == 0L || (a == Long.MIN_VALUE && b == -1L)) fail()
                a / b
            }
            '%' -> {
                if (b == 0L) fail()
                a % b
            }
            else -> error("unknown operator $op")
        }
    } catch (_: ArithmeticException) {
        fail()
    }

    private fun pushValue(v: Long) {
        if (valueCount == values.size) values = values.copyOf(values.size * 2)
        values[valueCount++] = v
    }

    private fun pushOp(op: Char) {
        if (opCount == ops.size) ops = ops.copyOf(ops.size * 2)
        ops[opCount++] = op
    }

    private companion object {
        const val UNARY_MINUS = 'u'

        fun precedence(op: Char): Int = when (op) {
            UNARY_MINUS -> 3
            '*', '/', '%' -> 2
            else -> 1
        }

        fun fail(): Nothing = throw CalcException()
    }
}

private fun String.isBlankLine(): Boolean = all { it == ' ' || it == '\t' }

fun main() {
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val out = PrintStream(BufferedOutputStream(System.out, 1 shl 16), false, Charsets.US_ASCII)
    val evaluator = Evaluator()
    val lines = input.split('\n')
    // A trailing newline yields one final empty element, which prints nothing anyway.
    for (line in lines) {
        if (line.isBlankLine()) continue
        out.println(evaluator.evaluate(line)?.toString() ?: "error")
    }
    out.flush()
}
