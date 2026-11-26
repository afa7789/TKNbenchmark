package lru

import java.io.BufferedOutputStream
import java.io.FileDescriptor
import java.io.FileOutputStream
import java.io.OutputStream

private val NULL_BYTES = "NULL".toByteArray(Charsets.US_ASCII)

fun main() {
    val input = System.`in`.readBytes()
    BufferedOutputStream(FileOutputStream(FileDescriptor.out), 1 shl 16).use { run(input, it) }
}

internal fun run(input: ByteArray, out: OutputStream) {
    val lines = LineReader(input)
    var first = lines.next()
    while (first != null && first.isBlank()) first = lines.next()
    if (first == null) return

    val cache = LruCache<String, String>(first.trim().toInt())
    while (true) {
        val line = lines.next() ?: break
        execute(cache, line, out)
    }
}

private fun execute(cache: LruCache<String, String>, line: String, out: OutputStream) {
    val firstSpace = line.indexOf(' ')
    val command = if (firstSpace < 0) line else line.substring(0, firstSpace)
    when (command) {
        "SET" -> {
            if (firstSpace < 0) return
            val secondSpace = line.indexOf(' ', firstSpace + 1)
            if (secondSpace < 0) return
            cache[line.substring(firstSpace + 1, secondSpace)] = line.substring(secondSpace + 1)
        }
        "GET" -> {
            if (firstSpace < 0) return
            val value = cache[line.substring(firstSpace + 1)]
            out.writeLine(value?.toByteArray(Charsets.ISO_8859_1) ?: NULL_BYTES)
        }
        "DEL" -> {
            if (firstSpace < 0) return
            out.write(if (cache.delete(line.substring(firstSpace + 1))) '1'.code else '0'.code)
            out.write('\n'.code)
        }
        "SIZE" -> out.writeLine(cache.size.toString().toByteArray(Charsets.US_ASCII))
        // Blank or unrecognised lines produce no output.
        else -> Unit
    }
}

private fun OutputStream.writeLine(bytes: ByteArray) {
    write(bytes)
    write('\n'.code)
}

/** Splits a byte buffer into lines, tolerating a trailing `\r` and a missing final newline. */
private class LineReader(private val data: ByteArray) {
    private var pos = 0

    fun next(): String? {
        if (pos >= data.size) return null
        val start = pos
        var end = start
        while (end < data.size && data[end] != '\n'.code.toByte()) end++
        pos = end + 1
        if (end > start && data[end - 1] == '\r'.code.toByte()) end--
        return String(data, start, end - start, Charsets.ISO_8859_1)
    }
}
