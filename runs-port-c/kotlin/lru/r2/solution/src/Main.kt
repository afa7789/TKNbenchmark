/*
 * lru — simulate an LRU cache driven by commands on standard input.
 *
 * Input is read in one go and decoded as ISO-8859-1 so every byte maps to
 * exactly one char and round-trips unchanged to the output.
 */
import kotlin.text.Charsets.ISO_8859_1

/** A fixed-capacity cache that evicts the least recently used key on overflow. */
class LruCache<K, V>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive" }
    }

    // accessOrder = true: get/put move the entry to the most-recently-used end.
    private val map = object : LinkedHashMap<K, V>(initialCapacity(capacity), LOAD_FACTOR, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = map.size

    operator fun get(key: K): V? = map[key]

    operator fun set(key: K, value: V) {
        map[key] = value
    }

    /** Removes [key]; returns true if it was present. */
    fun remove(key: K): Boolean = map.remove(key) != null

    private companion object {
        const val LOAD_FACTOR = 0.75f
        const val MAX_PRESIZE = 1 shl 21

        fun initialCapacity(capacity: Int): Int =
            (minOf(capacity, MAX_PRESIZE) / LOAD_FACTOR).toInt() + 1
    }
}

/** Parses the capacity line leniently: leading blanks, then digits; clamped to [1, Int.MAX_VALUE]. */
private fun parseCapacity(line: String): Int {
    val digits = line.trimStart(' ', '\t').takeWhile { it in '0'..'9' }
    val value = digits.fold(0L) { acc, c -> minOf(acc * 10 + (c - '0'), Int.MAX_VALUE.toLong()) }
    return value.toInt().coerceAtLeast(1)
}

/** Splits [line] on runs of spaces, dropping empty tokens. */
private fun tokenize(line: String): List<String> = line.split(' ').filter { it.isNotEmpty() }

fun main() {
    val input = System.`in`.readBytes().toString(ISO_8859_1)
    val out = System.out.bufferedWriter(ISO_8859_1)
    fun emit(text: String) {
        out.write(text)
        out.append('\n')
    }

    // A trailing newline terminates the last line rather than starting a new one.
    val lines = input.removeSuffix("\n").splitToSequence('\n').map { it.removeSuffix("\r") }.iterator()
    val cache = LruCache<String, String>(parseCapacity(lines.next()))

    for (line in lines) {
        val tokens = tokenize(line)
        val arg = { i: Int -> tokens.getOrElse(i) { "" } }
        when (tokens.firstOrNull()) {
            "SET" -> if (arg(1).isNotEmpty()) cache[arg(1)] = arg(2)
            "GET" -> emit(cache[arg(1)] ?: "NULL")
            "DEL" -> emit(if (cache.remove(arg(1))) "1" else "0")
            "SIZE" -> emit(cache.size.toString())
        }
    }
    out.flush()
}
