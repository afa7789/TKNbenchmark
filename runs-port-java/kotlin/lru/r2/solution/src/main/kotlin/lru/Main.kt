package lru

import java.io.BufferedReader
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.Writer

private const val BUFFER_SIZE = 1 shl 16

/** Reads LRU cache commands from standard input and writes results to standard output. */
fun main() {
    val input = FileInputStream(FileDescriptor.`in`).reader(Charsets.ISO_8859_1).buffered(BUFFER_SIZE)
    val output = FileOutputStream(FileDescriptor.out).writer(Charsets.ISO_8859_1).buffered(BUFFER_SIZE)
    input.use { reader -> output.use { writer -> run(reader, writer) } }
}

internal fun run(input: BufferedReader, output: Writer) {
    val header = input.readLine() ?: return
    val cache = LruCache<String, String>(header.trim().toInt())
    while (true) {
        val line = input.readLine() ?: break
        execute(cache, line.removeSuffix("\r"), output)
    }
}

private fun execute(cache: LruCache<String, String>, line: String, output: Writer) {
    val command = line.substringBefore(' ')
    val args = line.substringAfter(' ', missingDelimiterValue = "")
    val hasArgs = command.length < line.length
    when (command) {
        "SET" -> {
            val separator = args.indexOf(' ')
            if (hasArgs && separator >= 0) {
                cache[args.substring(0, separator)] = args.substring(separator + 1)
            }
        }
        "GET" -> if (hasArgs) output.writeLine(cache[args] ?: "NULL")
        "DEL" -> if (hasArgs) output.writeLine(if (cache.remove(args)) "1" else "0")
        "SIZE" -> output.writeLine(cache.size.toString())
        // Blank or unrecognised lines are ignored.
    }
}

private fun Writer.writeLine(text: String) {
    write(text)
    write('\n'.code)
}
