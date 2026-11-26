// LRU cache simulator: reads a capacity and a stream of commands from stdin
// and writes command results to stdout. See SPEC.md.

import java.io.BufferedOutputStream

/** Iterates over the space-delimited tokens of a single line, skipping runs of spaces. */
private class Tokenizer(private val line: String) {
    private var pos = 0

    /** Returns the next token, or an empty string when the line is exhausted. */
    fun next(): String {
        while (pos < line.length && line[pos] == ' ') pos++
        val start = pos
        while (pos < line.length && line[pos] != ' ') pos++
        return line.substring(start, pos)
    }
}

/** Splits [text] on '\n', tolerating a missing final newline and a stray '\r' before each newline. */
private fun lines(text: String): Sequence<String> = sequence {
    var start = 0
    while (start < text.length) {
        val nl = text.indexOf('\n', start)
        val end = if (nl < 0) text.length else nl
        val trimmedEnd = if (end > start && text[end - 1] == '\r') end - 1 else end
        yield(text.substring(start, trimmedEnd))
        start = end + 1
    }
}

/**
 * Parses the leading decimal digits of the first token. Mirrors `std::from_chars`:
 * no digits or an out-of-range value yields 0.
 */
private fun parseCapacity(line: String): Int {
    val token = Tokenizer(line).next()
    val digits = token.takeWhile { it in '0'..'9' }
    return digits.toIntOrNull() ?: 0
}

private fun execute(cache: LruCache<String, String>, line: String, out: StringBuilder) {
    val tokens = Tokenizer(line)
    when (tokens.next()) {
        "SET" -> {
            val key = tokens.next()
            val value = tokens.next()
            if (key.isNotEmpty() && value.isNotEmpty()) cache[key] = value
        }
        "GET" -> out.append(cache[tokens.next()] ?: "NULL").append('\n')
        "DEL" -> out.append(if (cache.remove(tokens.next())) "1\n" else "0\n")
        "SIZE" -> out.append(cache.size).append('\n')
        // Blank or unrecognised lines produce no output.
    }
}

fun main() {
    // Latin-1 maps bytes to chars one-to-one, so arbitrary input round-trips unchanged.
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val lineIterator = lines(input).iterator()
    if (!lineIterator.hasNext()) return

    val cache = LruCache<String, String>(parseCapacity(lineIterator.next()))
    val out = StringBuilder(1 shl 20)
    lineIterator.forEach { execute(cache, it, out) }

    BufferedOutputStream(System.out, 1 shl 16).use { stream ->
        stream.write(out.toString().toByteArray(Charsets.ISO_8859_1))
    }
}
