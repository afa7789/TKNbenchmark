// LRU cache simulator: reads a capacity and a stream of commands from stdin.
import java.io.BufferedOutputStream
import java.io.PrintStream

/** Fixed-capacity cache that evicts the least recently used key once it holds more than [capacity] keys. */
class LruCache(private val capacity: Int) {
    // Access-ordered map: iteration starts at the least recently used entry.
    private val entries = object : LinkedHashMap<String, String>(initialCapacity(capacity), 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Inserts or overwrites [key]; either way it becomes the most recently used. */
    operator fun set(key: String, value: String) {
        entries[key] = value
    }

    /** Returns the value for [key], marking it most recently used, or null on a miss. */
    operator fun get(key: String): String? = entries[key]

    /** Removes [key]; returns whether it was present. */
    fun remove(key: String): Boolean = entries.remove(key) != null

    private companion object {
        fun initialCapacity(capacity: Int): Int = (minOf(capacity + 1, 1 shl 20) / 0.75f).toInt() + 1
    }
}

/** Cursor over the raw input that yields trimmed lines and space-separated tokens. */
private class Scanner(private val text: String) {
    private var pos = 0

    fun nextLine(): String? {
        if (pos >= text.length) return null
        val end = text.indexOf('\n', pos).let { if (it < 0) text.length else it }
        val line = text.substring(pos, end)
        pos = end + 1
        return line.trim { it == ' ' || it == '\t' || it == '\r' }
    }
}

/** Splits [line] at single spaces, mirroring a strict single-separator tokenizer. */
private fun tokens(line: String): List<String> = line.split(' ')

/** Parses the leading decimal digits of [s]; yields 0 when there are none or the value overflows. */
private fun parseCapacity(s: String): Int {
    val digits = s.takeWhile { it in '0'..'9' }
    val value = digits.toLongOrNull() ?: return 0
    return value.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
}

fun main() {
    // Latin-1 maps bytes 1:1 to chars, so any input bytes round-trip unchanged.
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val scanner = Scanner(input)
    val cache = LruCache(scanner.nextLine()?.let(::parseCapacity) ?: 0)

    val out = StringBuilder(1 shl 16)
    while (true) {
        val line = scanner.nextLine() ?: break
        val parts = tokens(line)
        val arg1 = parts.getOrElse(1) { "" }
        when (parts[0]) {
            "SET" -> cache[arg1] = parts.getOrElse(2) { "" }
            "GET" -> out.append(cache[arg1] ?: "NULL").append('\n')
            "DEL" -> out.append(if (cache.remove(arg1)) "1\n" else "0\n")
            "SIZE" -> out.append(cache.size).append('\n')
        }
    }

    PrintStream(BufferedOutputStream(System.out, 1 shl 16), false, Charsets.ISO_8859_1).use { it.print(out) }
}
