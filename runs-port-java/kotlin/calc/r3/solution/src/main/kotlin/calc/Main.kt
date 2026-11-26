package calc

import java.io.BufferedReader
import java.io.Writer

/** Generous stack so deeply nested expressions do not overflow the recursive parser. */
private const val STACK_SIZE_BYTES = 1L shl 30

private const val BUFFER_SIZE = 1 shl 16

/**
 * Entry point: reads one expression per line from standard input and prints
 * its value or `error`. Blank lines produce no output.
 */
fun main() {
    val worker = Thread(null, ::run, "calc", STACK_SIZE_BYTES)
    worker.start()
    worker.join()
}

private fun run() {
    // ISO-8859-1 maps every byte to a char, so arbitrary input bytes never fail decoding;
    // any non-ASCII byte is simply an invalid token.
    System.`in`.reader(Charsets.ISO_8859_1).buffered(BUFFER_SIZE).use { input ->
        System.out.writer(Charsets.US_ASCII).buffered(BUFFER_SIZE).use { output ->
            process(input, output)
        }
    }
}

private fun process(input: BufferedReader, output: Writer) {
    while (true) {
        val line = input.readLfLine() ?: return
        if (line.all { it.isBlankChar() }) continue
        output.write(evaluate(line))
        output.write('\n'.code)
    }
}

/**
 * Reads a line terminated by `'\n'` only (unlike [BufferedReader.readLine],
 * a `'\r'` is kept so that it is rejected as an invalid character).
 *
 * @return the line without its terminator, or `null` at end of input
 */
private fun BufferedReader.readLfLine(): String? {
    val sb = StringBuilder()
    while (true) {
        val c = read()
        when {
            c == -1 -> return if (sb.isEmpty()) null else sb.toString()
            c == '\n'.code -> return sb.toString()
            else -> sb.append(c.toChar())
        }
    }
}

private fun evaluate(line: String): String = try {
    Parser.evaluate(line).toString()
} catch (e: CalcException) {
    "error"
} catch (e: StackOverflowError) {
    "error"
}
