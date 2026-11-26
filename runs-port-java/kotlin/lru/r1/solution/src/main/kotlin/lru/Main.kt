package lru

import java.io.BufferedReader
import java.io.Writer

private const val BUFFER_SIZE = 1 shl 16

/**
 * Reads a capacity followed by cache commands from standard input and writes
 * command results to standard output, one per line.
 */
fun main() {
    val input = System.`in`.reader(Charsets.ISO_8859_1).buffered(BUFFER_SIZE)
    val output = System.out.writer(Charsets.ISO_8859_1).buffered(BUFFER_SIZE)
    output.use { run(input, it) }
}

internal fun run(input: BufferedReader, output: Writer) {
    val header = input.readLine() ?: return
    val cache = LruCache<String, String>(header.trim().toInt())
    input.lineSequence().forEach { line -> cache.execute(line.removeSuffix("\r"), output) }
}

private fun LruCache<String, String>.execute(line: String, output: Writer) {
    val firstSpace = line.indexOf(' ')
    val command = if (firstSpace < 0) line else line.substring(0, firstSpace)
    when (command) {
        "SET" -> {
            val secondSpace = line.indexOf(' ', firstSpace + 1)
            if (secondSpace < 0) return
            this[line.substring(firstSpace + 1, secondSpace)] = line.substring(secondSpace + 1)
        }
        "GET" -> {
            if (firstSpace < 0) return
            output.writeLine(this[line.substring(firstSpace + 1)] ?: "NULL")
        }
        "DEL" -> {
            if (firstSpace < 0) return
            output.writeLine(if (remove(line.substring(firstSpace + 1))) "1" else "0")
        }
        "SIZE" -> output.writeLine(size.toString())
        else -> Unit // Blank or unrecognised lines are ignored.
    }
}

private fun Writer.writeLine(text: String) {
    write(text)
    write('\n'.code)
}
