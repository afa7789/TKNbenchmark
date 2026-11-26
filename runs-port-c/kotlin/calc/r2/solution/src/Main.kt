/*
 * calc: evaluate one 64-bit signed integer expression per input line.
 *
 * Parsing uses an iterative operator-precedence (shunting-yard) evaluator
 * with explicit stacks, so arbitrarily deep nesting cannot exhaust the
 * call stack.
 */
package calc

import java.io.BufferedOutputStream

private const val LPAREN = '('.code.toByte()
private const val NEG = 'n'.code.toByte()
private const val ADD = '+'.code.toByte()
private const val SUB = '-'.code.toByte()
private const val MUL = '*'.code.toByte()
private const val DIV = '/'.code.toByte()
private const val MOD = '%'.code.toByte()
private const val RPAREN = ')'.code.toByte()
private const val NEWLINE = '\n'.code.toByte()

private fun isBlank(c: Byte): Boolean = c == ' '.code.toByte() || c == '\t'.code.toByte()

private fun isDigit(c: Byte): Boolean = c >= '0'.code.toByte() && c <= '9'.code.toByte()

private fun precedence(op: Byte): Int = when (op) {
    NEG -> 3
    MUL, DIV, MOD -> 2
    ADD, SUB -> 1
    else -> 0 // '(' never reduces by precedence
}

/** Signals a syntax or arithmetic error while evaluating a line. */
private class EvalException : RuntimeException(null, null, false, false)

private val evalError = EvalException()

/**
 * Evaluator with reusable value and operator stacks.
 * Every token occupies at least one byte, so a line of length n needs at most n + 1 slots.
 */
class Evaluator {
    private var values = LongArray(64)
    private var ops = ByteArray(64)
    private var valueCount = 0
    private var opCount = 0

    private fun reserve(need: Int) {
        if (need <= values.size) return
        var cap = values.size
        while (cap < need) cap *= 2
        values = values.copyOf(cap)
        ops = ops.copyOf(cap)
    }

    private fun applyBinary(op: Byte, a: Long, b: Long): Long = try {
        when (op) {
            ADD -> Math.addExact(a, b)
            SUB -> Math.subtractExact(a, b)
            MUL -> Math.multiplyExact(a, b)
            DIV -> if (b == 0L || (a == Long.MIN_VALUE && b == -1L)) throw evalError else a / b
            MOD -> when (b) {
                0L -> throw evalError
                -1L -> 0L
                else -> a % b
            }
            else -> throw evalError
        }
    } catch (_: ArithmeticException) {
        throw evalError
    }

    /** Pops the top operator and applies it to the value stack. */
    private fun reduceOne() {
        val op = ops[--opCount]
        if (op == NEG) {
            val v = values[valueCount - 1]
            if (v == Long.MIN_VALUE) throw evalError
            values[valueCount - 1] = -v
            return
        }
        val b = values[--valueCount]
        values[valueCount - 1] = applyBinary(op, values[valueCount - 1], b)
    }

    /** Reduces while the top operator binds at least as tightly as [prec]. */
    private fun reduceWhile(prec: Int) {
        while (opCount > 0 && ops[opCount - 1] != LPAREN && precedence(ops[opCount - 1]) >= prec) {
            reduceOne()
        }
    }

    /** Evaluates `line[start, end)`, returning its value or `null` on any error. */
    fun evaluate(line: ByteArray, start: Int, end: Int): Long? = try {
        evaluateOrThrow(line, start, end)
    } catch (_: EvalException) {
        null
    }

    private fun evaluateOrThrow(line: ByteArray, start: Int, end: Int): Long {
        reserve(end - start + 1)
        valueCount = 0
        opCount = 0

        var wantOperand = true
        var i = start
        while (true) {
            while (i < end && isBlank(line[i])) i++

            if (wantOperand) {
                if (i == end) throw evalError
                val c = line[i]
                when {
                    c == SUB -> { ops[opCount++] = NEG; i++ }
                    c == LPAREN -> { ops[opCount++] = LPAREN; i++ }
                    isDigit(c) -> {
                        var v = 0L
                        var overflow = false
                        do {
                            val d = line[i] - '0'.code.toByte()
                            if (v > (Long.MAX_VALUE - d) / 10) overflow = true else v = v * 10 + d
                            i++
                        } while (i < end && isDigit(line[i]))
                        if (overflow) throw evalError
                        values[valueCount++] = v
                        wantOperand = false
                    }
                    else -> throw evalError
                }
                continue
            }

            if (i == end) break

            when (val c = line[i++]) {
                RPAREN -> {
                    reduceWhile(0)
                    if (opCount == 0) throw evalError // unmatched ')'
                    opCount-- // discard '('
                }
                ADD, SUB, MUL, DIV, MOD -> {
                    reduceWhile(precedence(c))
                    ops[opCount++] = c
                    wantOperand = true
                }
                else -> throw evalError
            }
        }

        reduceWhile(0)
        if (opCount != 0) throw evalError // unmatched '('
        return values[0]
    }
}

private fun isBlankLine(line: ByteArray, start: Int, end: Int): Boolean =
    (start until end).all { isBlank(line[it]) }

fun main() {
    val input = System.`in`.readBytes()
    val out = BufferedOutputStream(System.out, 1 shl 16)
    val evaluator = Evaluator()
    val errorBytes = "error\n".toByteArray()

    var pos = 0
    while (pos < input.size) {
        var nl = pos
        while (nl < input.size && input[nl] != NEWLINE) nl++
        val start = pos
        pos = if (nl < input.size) nl + 1 else nl

        if (isBlankLine(input, start, nl)) continue

        val value = evaluator.evaluate(input, start, nl)
        if (value != null) {
            out.write(value.toString().toByteArray())
            out.write(NEWLINE.toInt())
        } else {
            out.write(errorBytes)
        }
    }
    out.flush()
}
