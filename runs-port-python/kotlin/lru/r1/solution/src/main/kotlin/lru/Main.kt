package lru

import java.io.BufferedOutputStream
import java.io.OutputStream

/**
 * Least-recently-used cache with a fixed [capacity].
 *
 * Backed by an access-ordered [LinkedHashMap], so lookups, insertions, removals and
 * evictions all run in O(1) expected time.
 */
class LruCache<K, V>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive: $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(initialCapacity(capacity), LOAD_FACTOR, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Inserts or overwrites [key]; it becomes the most recently used, evicting the LRU key if over capacity. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Returns the value for [key], marking it most recently used, or `null` on a miss. */
    operator fun get(key: K): V? = entries[key]

    /** Removes [key], returning whether it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null

    private companion object {
        const val LOAD_FACTOR = 0.75f
        const val MAX_PREALLOCATED = 1 shl 16

        fun initialCapacity(capacity: Int): Int = (minOf(capacity, MAX_PREALLOCATED) / LOAD_FACTOR).toInt() + 1
    }
}

/** Splits a byte buffer into whitespace-separated tokens, one line at a time. */
private class LineTokenizer(private val data: ByteArray) {
    private var pos = 0

    fun hasMoreLines(): Boolean = pos < data.size

    /** Reads the tokens of the next line (terminated by `\n` or end of input) into [out]. */
    fun nextLine(out: MutableList<String>) {
        out.clear()
        val end = data.indexOf(NEWLINE, pos).let { if (it < 0) data.size else it }
        var i = pos
        while (i < end) {
            while (i < end && isSpace(data[i])) i++
            val start = i
            while (i < end && !isSpace(data[i])) i++
            if (i > start) out += String(data, start, i - start, Charsets.ISO_8859_1)
        }
        pos = end + 1
    }

    private companion object {
        const val NEWLINE = '\n'.code.toByte()

        fun ByteArray.indexOf(b: Byte, from: Int): Int {
            for (i in from until size) if (this[i] == b) return i
            return -1
        }

        fun isSpace(b: Byte): Boolean = when (b.toInt()) {
            0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D -> true
            else -> false
        }
    }
}

/** Executes cache commands from [input], writing one output line per producing command to [output]. */
fun simulate(input: ByteArray, output: OutputStream) {
    val lines = LineTokenizer(input)
    val tokens = ArrayList<String>(4)
    if (!lines.hasMoreLines()) return
    lines.nextLine(tokens)
    val capacity = tokens.singleOrNull()?.toIntOrNull() ?: return
    val cache = LruCache<String, String>(capacity)

    fun emit(text: String) {
        output.write(text.toByteArray(Charsets.ISO_8859_1))
        output.write('\n'.code)
    }

    while (lines.hasMoreLines()) {
        lines.nextLine(tokens)
        when (tokens.firstOrNull()) {
            "SET" -> if (tokens.size >= 3) cache[tokens[1]] = tokens[2]
            "GET" -> if (tokens.size >= 2) emit(cache[tokens[1]] ?: "NULL")
            "DEL" -> if (tokens.size >= 2) emit(if (cache.remove(tokens[1])) "1" else "0")
            "SIZE" -> emit(cache.size.toString())
        }
    }
}

fun main() {
    val input = System.`in`.readBytes()
    BufferedOutputStream(System.out, 1 shl 16).use { simulate(input, it) }
}
