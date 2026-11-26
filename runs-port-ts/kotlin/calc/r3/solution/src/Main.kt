package calc

import java.io.BufferedWriter
import java.io.OutputStreamWriter

private fun evaluateLine(line: String): String =
    try {
        evaluate(line).toString()
    } catch (_: EvalException) {
        "error"
    }

fun main() {
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val lines = input.split('\n').let { if (it.last().isEmpty()) it.dropLast(1) else it }

    BufferedWriter(OutputStreamWriter(System.out, Charsets.ISO_8859_1), 1 shl 16).use { out ->
        for (line in lines) {
            if (isBlankLine(line)) continue
            out.write(evaluateLine(line))
            out.write('\n'.code)
        }
    }
}
