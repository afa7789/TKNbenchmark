package lru

import java.io.BufferedOutputStream
import java.io.OutputStream
import kotlin.system.exitProcess

/**
 * LRU cache simulator: the first input line holds the capacity, each later
 * line is a `SET`, `GET`, `DEL` or `SIZE` command. Malformed or unknown
 * commands are ignored; an invalid capacity line means there is nothing to do.
 */
fun main() {
    val input = System.`in`.readBytes()
    val reader = LineReader(input)
    val capacity = reader.nextLine()?.let(::parseCapacity) ?: return

    val cache = LruCache<String, String>(capacity, expectedEntries = countLines(input))
    val out = BufferedOutputStream(System.out, OUTPUT_BUFFER_SIZE)
    while (true) {
        val line = reader.nextLine() ?: break
        runCommand(cache, line, out)
    }
    out.flush()
    exitProcess(0)
}

private const val OUTPUT_BUFFER_SIZE = 1 shl 16
private const val MAX_CAPACITY_DIGITS = 18
private val NULL_BYTES = "NULL".toByteArray(Charsets.ISO_8859_1)
private const val NEWLINE = '\n'.code

private fun runCommand(cache: LruCache<String, String>, line: Line, out: OutputStream) {
    val command = line.nextToken() ?: return // blank line
    when {
        command.contentEquals("GET") -> {
            val key = line.nextToken() ?: return
            val value = cache[key.asString()]
            out.writeLine(value?.toByteArray(Charsets.ISO_8859_1) ?: NULL_BYTES)
        }
        command.contentEquals("SET") -> {
            val key = line.nextToken() ?: return
            val value = line.nextToken() ?: return
            cache[key.asString()] = value.asString()
        }
        command.contentEquals("DEL") -> {
            val key = line.nextToken() ?: return
            out.writeLine(if (cache.remove(key.asString())) "1" else "0")
        }
        command.contentEquals("SIZE") -> out.writeLine(cache.size.toString())
        // Unknown commands are ignored.
    }
}

/** Parses the capacity from the first token of [line]; `null` if it is not a positive integer. */
private fun parseCapacity(line: Line): Long? {
    val token = line.nextToken() ?: return null
    if (token.length > MAX_CAPACITY_DIGITS) return null
    var value = 0L
    for (i in 0 until token.length) {
        val digit = token[i] - '0'.code
        if (digit !in 0..9) return null
        value = value * 10 + digit
    }
    return value.takeIf { it > 0 }
}

private fun countLines(bytes: ByteArray): Int = 1 + bytes.count { it.toInt() == NEWLINE }

private fun OutputStream.writeLine(bytes: ByteArray) {
    write(bytes)
    write(NEWLINE)
}

private fun OutputStream.writeLine(text: String) = writeLine(text.toByteArray(Charsets.ISO_8859_1))

// ---------- input parsing over the raw byte buffer ----------

/** A byte range `[start, end)` of [bytes]. */
private class Slice(val bytes: ByteArray, val start: Int, val end: Int) {
    val length: Int get() = end - start

    operator fun get(index: Int): Int = bytes[start + index].toInt()

    fun contentEquals(word: String): Boolean =
        length == word.length && word.indices.all { this[it] == word[it].code }

    /** Bytes are mapped one-to-one onto chars, so arbitrary input round-trips unchanged. */
    fun asString(): String = String(bytes, start, length, Charsets.ISO_8859_1)
}

/** One input line whose space-separated tokens are consumed left to right. */
private class Line(private val bytes: ByteArray, private var pos: Int, private val end: Int) {
    fun nextToken(): Slice? {
        while (pos < end && bytes[pos] == SPACE) pos++
        if (pos == end) return null
        val start = pos
        while (pos < end && bytes[pos] != SPACE) pos++
        return Slice(bytes, start, pos)
    }

    private companion object {
        const val SPACE = ' '.code.toByte()
    }
}

/** Splits a buffer into lines on `\n`, dropping one trailing `\r` from each. */
private class LineReader(private val bytes: ByteArray) {
    private var pos = 0

    fun nextLine(): Line? {
        if (pos >= bytes.size) return null
        val start = pos
        var stop = start
        while (stop < bytes.size && bytes[stop] != LF) stop++
        pos = if (stop < bytes.size) stop + 1 else stop
        if (stop > start && bytes[stop - 1] == CR) stop--
        return Line(bytes, start, stop)
    }

    private companion object {
        const val LF = '\n'.code.toByte()
        const val CR = '\r'.code.toByte()
    }
}
