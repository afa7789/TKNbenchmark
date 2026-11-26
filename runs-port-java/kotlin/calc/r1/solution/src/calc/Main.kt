package calc

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.io.PrintStream

/** Deeply nested expressions are parsed recursively, so give the worker a generous stack. */
private const val STACK_SIZE_BYTES = 1L shl 30
private const val BUFFER_SIZE = 1 shl 16

/** Evaluates one expression per line of standard input and prints its value, or `error`. */
fun main() {
    var failure: IOException? = null
    val worker = Thread(null, {
        try {
            run(System.`in`, System.out)
        } catch (e: IOException) {
            failure = e
        }
    }, "calc", STACK_SIZE_BYTES)
    worker.start()
    worker.join()
    failure?.let { System.err.println("calc: ${it.message}") }
}

internal fun run(rawIn: InputStream, rawOut: OutputStream) {
    val input = rawIn.buffered(BUFFER_SIZE)
    val out = PrintStream(rawOut.buffered(BUFFER_SIZE), false, Charsets.US_ASCII)
    val line = ByteArrayOutputStream(256)
    while (true) {
        val b = input.read()
        if (b == -1) break
        if (b == '\n'.code) {
            emit(line, out)
            line.reset()
        } else {
            line.write(b)
        }
    }
    if (line.size() > 0) emit(line, out)
    out.flush()
}

private fun emit(line: ByteArrayOutputStream, out: PrintStream) {
    val bytes = line.toByteArray()
    if (Evaluator.isBlank(bytes)) return
    out.println(Evaluator.evaluate(bytes)?.toString() ?: "error")
}
