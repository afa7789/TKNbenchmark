package calc

import java.io.BufferedInputStream
import java.io.BufferedWriter
import java.io.InputStream
import java.io.OutputStreamWriter

private fun evaluateLine(line: CharSequence): String? =
    try {
        Evaluator.evaluate(line)?.toString()
    } catch (_: EvalException) {
        "error"
    }

/**
 * Calls [action] for each `\n`-terminated line of [input] (decoded as Latin-1,
 * so every byte maps to exactly one char). A final unterminated line is included.
 */
private inline fun forEachLine(input: InputStream, action: (CharSequence) -> Unit) {
    val buffer = ByteArray(1 shl 16)
    val line = StringBuilder()
    while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        for (k in 0 until read) {
            val b = buffer[k].toInt() and 0xFF
            if (b == '\n'.code) {
                action(line)
                line.setLength(0)
            } else {
                line.append(b.toChar())
            }
        }
    }
    if (line.isNotEmpty()) action(line)
}

fun main() {
    val out = BufferedWriter(OutputStreamWriter(System.out, Charsets.ISO_8859_1), 1 shl 16)
    forEachLine(BufferedInputStream(System.`in`)) { line ->
        evaluateLine(line)?.let {
            out.write(it)
            out.write('\n'.code)
        }
    }
    out.flush()
}
