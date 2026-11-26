/*
 * calc — a 64-bit signed integer expression evaluator.
 *
 * Reads one expression per line from standard input and prints its value or
 * "error". Parsing uses an explicit-stack operator-precedence algorithm, so
 * arbitrarily deep nesting cannot exhaust the call stack.
 */
package calc

import java.io.BufferedOutputStream
import java.io.InputStream
import java.io.PrintStream
import kotlin.system.exitProcess

/** Signals that an expression cannot be evaluated (syntax, division by zero or overflow). */
private class EvalException : RuntimeException(null, null, false, false)

private fun fail(): Nothing = throw EvalException()

private enum class Op(val precedence: Int) {
    LPAREN(0),
    ADD(1),
    SUB(1),
    MUL(2),
    DIV(2),
    MOD(2),
    NEG(3),
}

private fun Byte.isBlank(): Boolean = this == ' '.code.toByte() || this == '\t'.code.toByte()

private fun Byte.isDigit(): Boolean = this >= '0'.code.toByte() && this <= '9'.code.toByte()

private inline fun checked(block: () -> Long): Long =
    try {
        block()
    } catch (_: ArithmeticException) {
        fail()
    }

/** Evaluates expressions; working storage is reused across calls. */
class Evaluator {
    private var values = LongArray(256)
    private var ops = arrayOfNulls<Op>(256)
    private var nValues = 0
    private var nOps = 0

    /** Returns the value of `line[from until to]`, or null if it is an error. */
    fun evaluate(line: ByteArray, from: Int, to: Int): Long? {
        reserve(to - from)
        nValues = 0
        nOps = 0
        return try {
            run(line, from, to)
        } catch (_: EvalException) {
            null
        }
    }

    /** Each stack holds at most one entry per input byte. */
    private fun reserve(n: Int) {
        if (n <= values.size) return
        var cap = values.size
        while (cap < n) cap *= 2
        values = LongArray(cap)
        ops = arrayOfNulls(cap)
    }

    private fun run(line: ByteArray, from: Int, to: Int): Long {
        var wantOperand = true
        var i = from

        while (i < to) {
            val c = line[i]
            if (c.isBlank()) {
                i++
                continue
            }

            if (wantOperand) {
                if (c.isDigit()) {
                    var v = 0L
                    while (i < to && line[i].isDigit()) {
                        val d = line[i] - '0'.code.toByte()
                        if (v > (Long.MAX_VALUE - d) / 10) fail()
                        v = v * 10 + d
                        i++
                    }
                    values[nValues++] = v
                    wantOperand = false
                    continue
                }
                ops[nOps++] = when (c.toInt().toChar()) {
                    '-' -> Op.NEG
                    '(' -> Op.LPAREN
                    else -> fail()
                }
                i++
                continue
            }

            val op = when (c.toInt().toChar()) {
                '+' -> Op.ADD
                '-' -> Op.SUB
                '*' -> Op.MUL
                '/' -> Op.DIV
                '%' -> Op.MOD
                ')' -> {
                    while (nOps > 0 && ops[nOps - 1] != Op.LPAREN) applyTop()
                    if (nOps == 0) fail()
                    nOps--
                    i++
                    continue
                }
                else -> fail()
            }

            // All binary operators are left-associative.
            while (nOps > 0 && ops[nOps - 1]!!.precedence >= op.precedence) applyTop()
            ops[nOps++] = op
            wantOperand = true
            i++
        }

        if (wantOperand) fail()
        while (nOps > 0) {
            if (ops[nOps - 1] == Op.LPAREN) fail()
            applyTop()
        }
        return values[0]
    }

    /** Pops the top operator and applies it to the value stack. */
    private fun applyTop() {
        val op = ops[--nOps]!!
        if (op == Op.NEG) {
            values[nValues - 1] = checked { Math.negateExact(values[nValues - 1]) }
            return
        }
        val b = values[--nValues]
        val a = values[nValues - 1]
        values[nValues - 1] = when (op) {
            Op.ADD -> checked { Math.addExact(a, b) }
            Op.SUB -> checked { Math.subtractExact(a, b) }
            Op.MUL -> checked { Math.multiplyExact(a, b) }
            Op.DIV -> when {
                b == 0L -> fail()
                a == Long.MIN_VALUE && b == -1L -> fail()
                else -> a / b
            }
            Op.MOD -> if (b == 0L) fail() else a % b // Long.MIN_VALUE % -1 is 0 on the JVM
            Op.NEG, Op.LPAREN -> fail()
        }
    }
}

private fun isBlankLine(line: ByteArray, from: Int, to: Int): Boolean =
    (from until to).all { line[it].isBlank() }

/** Evaluates every line of [input], writing one result per non-blank line to [out]. */
fun process(input: InputStream, out: PrintStream) {
    val data = input.readBytes()
    val evaluator = Evaluator()
    var start = 0
    while (start < data.size) {
        var end = start
        while (end < data.size && data[end] != '\n'.code.toByte()) end++
        if (!isBlankLine(data, start, end)) {
            out.println(evaluator.evaluate(data, start, end)?.toString() ?: "error")
        }
        start = end + 1
    }
}

fun main() {
    val out = PrintStream(BufferedOutputStream(System.out, 1 shl 16), false, Charsets.US_ASCII)
    try {
        process(System.`in`, out)
    } catch (e: java.io.IOException) {
        System.err.println("calc: read error")
        out.flush()
        exitProcess(1)
    }
    out.flush()
    if (out.checkError()) exitProcess(1)
}
