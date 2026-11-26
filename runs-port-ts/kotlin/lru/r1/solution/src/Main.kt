import java.io.BufferedOutputStream
import java.io.OutputStream
import kotlin.system.exitProcess

private const val OUTPUT_BUFFER_SIZE = 1 shl 16

/** Writes newline-terminated Latin-1 lines through a single buffered stream. */
private class LineWriter(stream: OutputStream) {
    private val out = BufferedOutputStream(stream, OUTPUT_BUFFER_SIZE)

    fun line(text: String) {
        for (ch in text) out.write(ch.code)
        out.write('\n'.code)
    }

    fun flush() = out.flush()
}

/** Parses the leading decimal integer of [text] (after trimming), like `parseInt(text, 10)`. */
private fun parseLeadingInt(text: String): Int? {
    val s = text.trim()
    var i = 0
    val negative = s.startsWith('-')
    if (negative || s.startsWith('+')) i++
    val start = i
    var value = 0L
    while (i < s.length && s[i].isDigit() && value <= Int.MAX_VALUE) {
        value = value * 10 + (s[i] - '0')
        i++
    }
    if (i == start) return null
    return (if (negative) -value else value).coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
}

private fun run(input: String, out: LineWriter) {
    val lines = input.splitToSequence('\n').map { it.removeSuffix("\r") }.iterator()
    if (!lines.hasNext()) return
    val header = lines.next()
    if (header.isEmpty() && !lines.hasNext()) return

    val capacity = parseLeadingInt(header)
        ?: throw IllegalArgumentException("capacity must be a positive integer, got '$header'")
    val cache = LruCache<String, String>(capacity)

    for (line in lines) {
        if (line.isEmpty()) continue
        val first = line.indexOf(' ')
        val command = if (first == -1) line else line.substring(0, first)
        val argument = line.substring(first + 1)

        when (command) {
            "SET" -> {
                val second = line.indexOf(' ', first + 1)
                if (second != -1) cache[line.substring(first + 1, second)] = line.substring(second + 1)
            }
            "GET" -> out.line(cache[argument] ?: "NULL")
            "DEL" -> out.line(if (cache.remove(argument)) "1" else "0")
            "SIZE" -> out.line(cache.size.toString())
            // Unknown commands are ignored; the spec defines no output for them.
        }
    }
}

fun main() {
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val out = LineWriter(System.out)
    try {
        run(input, out)
    } catch (e: IllegalArgumentException) {
        out.flush()
        System.err.println("error: ${e.message}")
        exitProcess(1)
    }
    out.flush()
}
