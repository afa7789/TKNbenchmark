package calc

import java.io.InputStream
import java.io.OutputStream
import kotlin.system.exitProcess

/** Deeply nested parentheses recurse; run on a thread with a generous stack. */
private const val STACK_SIZE = 1L shl 30
private val ERROR = "error\n".toByteArray(Charsets.US_ASCII)

/** Reads one expression per line from standard input and prints its value or `error`. */
fun main() {
    var failure: Throwable? = null
    val worker = Thread(null, {
        try {
            run(System.`in`, System.out)
        } catch (t: Throwable) {
            failure = t
        }
    }, "calc", STACK_SIZE)
    worker.start()
    worker.join()
    failure?.let {
        it.printStackTrace()
        exitProcess(1)
    }
}

fun run(input: InputStream, output: OutputStream) {
    val out = output.buffered(1 shl 16)
    val reader = LineReader(input)
    while (reader.next()) {
        val line = reader.line
        val length = reader.length
        if ((0 until length).all { Evaluator.isBlank(line[it]) }) continue
        val result = try {
            "${Evaluator.evaluate(line, 0, length)}\n".toByteArray(Charsets.US_ASCII)
        } catch (_: EvaluationException) {
            ERROR
        } catch (_: StackOverflowError) {
            ERROR
        }
        out.write(result)
    }
    out.flush()
}

/** Minimal buffered reader that splits a byte stream on `'\n'`, reusing one line buffer. */
private class LineReader(private val input: InputStream) {
    private val buffer = ByteArray(1 shl 16)
    private var bufferPos = 0
    private var bufferLimit = 0

    /** Holds the current line in its first [length] bytes. */
    var line = ByteArray(256)
        private set
    var length = 0
        private set

    /** Advances to the next line; returns false at end of input. */
    fun next(): Boolean {
        length = 0
        var sawAny = false
        while (true) {
            if (bufferPos == bufferLimit) {
                bufferLimit = input.read(buffer).coerceAtLeast(0)
                bufferPos = 0
                if (bufferLimit == 0) return sawAny
            }
            sawAny = true
            val start = bufferPos
            while (bufferPos < bufferLimit && buffer[bufferPos] != NEWLINE) bufferPos++
            append(start, bufferPos)
            if (bufferPos < bufferLimit) {
                bufferPos++ // consume '\n'
                return true
            }
        }
    }

    private fun append(from: Int, to: Int) {
        val count = to - from
        if (length + count > line.size) {
            line = line.copyOf(maxOf(line.size * 2, length + count))
        }
        buffer.copyInto(line, length, from, to)
        length += count
    }

    private companion object {
        const val NEWLINE = '\n'.code.toByte()
    }
}
