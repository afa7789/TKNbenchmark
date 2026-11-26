// LRU cache simulator: reads a capacity and a stream of commands from stdin.
import java.io.BufferedOutputStream

/** A fixed-capacity cache that evicts the least recently used key on overflow. */
class LruCache(private val capacity: Int) {
    // Access-ordered map: iteration order runs from least to most recently used,
    // and both get() and put() on an existing key move it to the most-recent end.
    private val entries = object : LinkedHashMap<String, String>(initialCapacity(capacity), LOAD_FACTOR, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>): Boolean =
            size > this@LruCache.capacity
    }

    val size: Int get() = entries.size

    fun set(key: String, value: String) {
        entries[key] = value
    }

    /** Returns the value for [key], marking it most recently used, or null on a miss. */
    fun get(key: String): String? = entries[key]

    /** Removes [key]; returns true if it was present. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    private companion object {
        const val LOAD_FACTOR = 0.75f
        const val MAX_TABLE_SIZE = 1L shl 30

        fun initialCapacity(capacity: Int): Int =
            ((capacity + 1L) / LOAD_FACTOR + 1).toLong().coerceAtMost(MAX_TABLE_SIZE).toInt()
    }
}

/** Parses the leading decimal digits of [s], ignoring anything after them. */
fun parseCapacity(s: String): Int {
    var value = 0L
    for (c in s) {
        if (c !in '0'..'9') break
        value = (value * 10 + (c - '0')).coerceAtMost(Int.MAX_VALUE.toLong())
    }
    return value.toInt()
}

/** Splits [data] into lines on '\n', dropping one trailing '\r' per line and a final empty line. */
fun splitLines(data: String): Sequence<String> = sequence {
    var start = 0
    while (start < data.length) {
        val newline = data.indexOf('\n', start)
        val end = if (newline < 0) data.length else newline
        val trimmedEnd = if (end > start && data[end - 1] == '\r') end - 1 else end
        yield(data.substring(start, trimmedEnd))
        start = end + 1
    }
}

fun main() {
    // Input is ASCII by spec; Latin-1 maps bytes 1:1 so arbitrary bytes still round-trip.
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val lines = splitLines(input).iterator()
    if (!lines.hasNext()) return

    val cache = LruCache(parseCapacity(lines.next()))
    val out = StringBuilder(1 shl 20)

    for (line in lines) {
        val tokens = line.split(' ')
        val key = tokens.getOrElse(1) { "" }
        when (tokens[0]) {
            "SET" -> cache.set(key, tokens.getOrElse(2) { "" })
            "GET" -> out.append(cache.get(key) ?: "NULL").append('\n')
            "DEL" -> out.append(if (cache.delete(key)) "1\n" else "0\n")
            "SIZE" -> out.append(cache.size).append('\n')
        }
    }

    BufferedOutputStream(System.out, 1 shl 16).use {
        it.write(out.toString().toByteArray(Charsets.ISO_8859_1))
    }
}
