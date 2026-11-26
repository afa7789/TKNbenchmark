/*
 * calc: evaluates one 64-bit signed integer expression per input line.
 *
 * The evaluator is an iterative operator-precedence (shunting-yard) parser
 * with explicit growable stacks, so arbitrarily deep nesting cannot exhaust
 * the call stack.
 */
import java.io.BufferedInputStream
import java.io.InputStream
import java.io.PrintStream

/** Thrown for any syntax, overflow or division-by-zero error; carries no stack trace. */
private object EvalError : RuntimeException() {
    override fun fillInStackTrace(): Throwable = this
}

private fun fail(): Nothing = throw EvalError

private fun ensure(condition: Boolean) {
    if (!condition) fail()
}

/* ---------- checked arithmetic ---------- */

private fun checkedAdd(a: Long, b: Long): Long = try {
    Math.addExact(a, b)
} catch (_: ArithmeticException) {
    fail()
}

private fun checkedSub(a: Long, b: Long): Long = try {
    Math.subtractExact(a, b)
} catch (_: ArithmeticException) {
    fail()
}

private fun checkedMul(a: Long, b: Long): Long = try {
    Math.multiplyExact(a, b)
} catch (_: ArithmeticException) {
    fail()
}

private fun checkedDiv(a: Long, b: Long): Long {
    ensure(b != 0L && !(a == Long.MIN_VALUE && b == -1L))
    return a / b
}

private fun checkedRem(a: Long, b: Long): Long {
    ensure(b != 0L)
    return a % b // JVM defines Long.MIN_VALUE % -1 as 0
}

private fun checkedNeg(a: Long): Long {
    ensure(a != Long.MIN_VALUE)
    return -a
}

/* ---------- growable stacks ---------- */

private class LongStack {
    private var data = LongArray(64)
    var size = 0
        private set

    fun clear() {
        size = 0
    }

    fun push(v: Long) {
        if (size == data.size) data = data.copyOf(size * 2)
        data[size++] = v
    }

    fun pop(): Long = data[--size]

    var top: Long
        get() = data[size - 1]
        set(v) {
            data[size - 1] = v
        }
}

private class ByteStack {
    private var data = ByteArray(64)
    var size = 0
        private set

    fun clear() {
        size = 0
    }

    fun push(v: Byte) {
        if (size == data.size) data = data.copyOf(size * 2)
        data[size++] = v
    }

    fun pop(): Byte = data[--size]

    fun peek(): Byte = data[size - 1]
}

/* ---------- evaluator ---------- */

private const val PLUS = '+'.code.toByte()
private const val MINUS = '-'.code.toByte()
private const val TIMES = '*'.code.toByte()
private const val DIVIDE = '/'.code.toByte()
private const val REMAINDER = '%'.code.toByte()
private const val LPAREN = '('.code.toByte()
private const val RPAREN = ')'.code.toByte()
private const val NEGATE = 'n'.code.toByte()
private const val SPACE = ' '.code.toByte()
private const val TAB = '\t'.code.toByte()
private const val ZERO = '0'.code.toByte()
private const val NINE = '9'.code.toByte()

private fun isBlank(b: Byte) = b == SPACE || b == TAB

private fun isDigit(b: Byte) = b in ZERO..NINE

private fun precedence(op: Byte): Int = when (op) {
    PLUS, MINUS -> 1
    TIMES, DIVIDE, REMAINDER -> 2
    NEGATE -> 3
    else -> 0 // '(' never pops
}

/** Reusable evaluator; its stacks persist across lines to avoid reallocation. */
class Evaluator {
    private val values = LongStack()
    private val ops = ByteStack()

    /** Returns the value of `line[0 until len]`, or null on any error. */
    fun evaluate(line: ByteArray, len: Int): Long? = try {
        run(line, len)
    } catch (_: EvalError) {
        null
    }

    private fun run(line: ByteArray, len: Int): Long {
        values.clear()
        ops.clear()
        var expectOperand = true
        var i = 0

        while (true) {
            while (i < len && isBlank(line[i])) i++
            if (i == len) break

            val c = line[i]
            if (expectOperand) {
                when {
                    isDigit(c) -> {
                        var v = 0L
                        do {
                            val d = line[i] - ZERO
                            ensure(v <= (Long.MAX_VALUE - d) / 10)
                            v = v * 10 + d
                            i++
                        } while (i < len && isDigit(line[i]))
                        values.push(v)
                        expectOperand = false
                    }
                    c == MINUS -> { ops.push(NEGATE); i++ }
                    c == LPAREN -> { ops.push(LPAREN); i++ }
                    else -> fail()
                }
            } else {
                when (c) {
                    PLUS, MINUS, TIMES, DIVIDE, REMAINDER -> {
                        reduce(precedence(c))
                        ops.push(c)
                        expectOperand = true
                    }
                    RPAREN -> {
                        reduce(0)
                        ensure(ops.size > 0) // unmatched ')'
                        ops.pop() // discard '('
                    }
                    else -> fail()
                }
                i++
            }
        }

        ensure(!expectOperand)
        reduce(0)
        ensure(ops.size == 0 && values.size == 1)
        return values.top
    }

    /** Pops and applies operators whose precedence is at least [minPrec]. */
    private fun reduce(minPrec: Int) {
        while (ops.size > 0) {
            val top = ops.peek()
            if (top == LPAREN || precedence(top) < minPrec) break
            ops.pop()
            apply(top)
        }
    }

    private fun apply(op: Byte) {
        if (op == NEGATE) {
            ensure(values.size >= 1)
            values.top = checkedNeg(values.top)
            return
        }
        ensure(values.size >= 2)
        val b = values.pop()
        val a = values.top
        values.top = when (op) {
            PLUS -> checkedAdd(a, b)
            MINUS -> checkedSub(a, b)
            TIMES -> checkedMul(a, b)
            DIVIDE -> checkedDiv(a, b)
            REMAINDER -> checkedRem(a, b)
            else -> fail()
        }
    }
}

/* ---------- I/O ---------- */

/** Reads raw byte lines (without the trailing '\n') into a reusable buffer. */
private class LineReader(private val input: InputStream) {
    var buffer = ByteArray(256)
        private set
    var length = 0
        private set

    /** Reads the next line; returns false at end of input. */
    fun next(): Boolean {
        length = 0
        while (true) {
            val c = input.read()
            if (c < 0) return length > 0
            if (c == '\n'.code) return true
            if (length == buffer.size) buffer = buffer.copyOf(length * 2)
            buffer[length++] = c.toByte()
        }
    }
}

private fun isBlankLine(line: ByteArray, len: Int): Boolean =
    (0 until len).all { isBlank(line[it]) }

fun main() {
    val reader = LineReader(BufferedInputStream(System.`in`, 1 shl 16))
    val out = PrintStream(System.out.buffered(1 shl 16), false, Charsets.US_ASCII)
    val evaluator = Evaluator()

    while (reader.next()) {
        val line = reader.buffer
        val len = reader.length
        if (isBlankLine(line, len)) continue
        out.print(evaluator.evaluate(line, len)?.toString() ?: "error")
        out.print('\n')
    }
    out.flush()
}
