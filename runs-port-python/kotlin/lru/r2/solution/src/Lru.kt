/** Simulate an LRU cache driven by commands read from standard input. */

import java.io.BufferedOutputStream
import java.io.OutputStream
import kotlin.system.exitProcess

/** A fixed-capacity cache that evicts its least recently used key on overflow. */
class LruCache<K, V>(private val capacity: Long) {
    private val entries = object : LinkedHashMap<K, V>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Returns the value for [key], marking it most recently used on a hit. */
    operator fun get(key: K): V? = entries[key]

    /** Inserts or overwrites [key], marking it most recently used. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key], returning whether it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null
}

private fun isSpace(b: Byte): Boolean =
    b == ' '.code.toByte() || (b >= 0x09 && b <= 0x0d)

/**
 * Parses an integer the way Python's `int()` does for ASCII input: surrounding whitespace,
 * an optional sign, and digits optionally grouped by single underscores. Values beyond the
 * Long range saturate, which is indistinguishable for a cache capacity.
 */
internal fun parseCapacity(bytes: ByteArray, from: Int, to: Int): Long? {
    var start = from
    var end = to
    while (start < end && isSpace(bytes[start])) start++
    while (end > start && isSpace(bytes[end - 1])) end--
    if (start == end) return null

    var negative = false
    when (bytes[start]) {
        '-'.code.toByte() -> { negative = true; start++ }
        '+'.code.toByte() -> start++
    }
    if (start == end) return null

    var value = 0L
    var previousWasDigit = false
    for (i in start until end) {
        val b = bytes[i]
        when {
            b in '0'.code.toByte()..'9'.code.toByte() -> {
                val digit = b - '0'.code.toByte()
                value = if (value > (Long.MAX_VALUE - digit) / 10) Long.MAX_VALUE else value * 10 + digit
                previousWasDigit = true
            }
            b == '_'.code.toByte() && previousWasDigit && i + 1 < end -> previousWasDigit = false
            else -> return null
        }
    }
    if (!previousWasDigit) return null
    return if (negative) -value else value
}

/** Splits `bytes[from, to)` into whitespace-separated tokens, like Python's `bytes.split()`. */
private fun tokenize(bytes: ByteArray, from: Int, to: Int, tokens: MutableList<String>) {
    tokens.clear()
    var i = from
    while (i < to) {
        while (i < to && isSpace(bytes[i])) i++
        if (i == to) break
        val start = i
        while (i < to && !isSpace(bytes[i])) i++
        tokens += String(bytes, start, i - start, Charsets.ISO_8859_1)
    }
}

/** Executes the command script in [input], writing one line per output to [output]. */
fun run(input: ByteArray, output: OutputStream) {
    var lineEnd = input.indexOfFirst(0, '\n'.code.toByte())
    val capacity = parseCapacity(input, 0, lineEnd) ?: return

    val cache = LruCache<String, String>(capacity)
    val writer = output.bufferedWriter(Charsets.ISO_8859_1)
    val tokens = ArrayList<String>(4)

    while (lineEnd < input.size) {
        val lineStart = lineEnd + 1
        lineEnd = input.indexOfFirst(lineStart, '\n'.code.toByte())
        tokenize(input, lineStart, lineEnd, tokens)
        if (tokens.isEmpty()) continue

        val result: String? = when (tokens[0]) {
            "GET" -> tokens.getOrNull(1)?.let { cache[it] ?: "NULL" }
            "SET" -> {
                if (tokens.size >= 3) cache[tokens[1]] = tokens[2]
                null
            }
            "DEL" -> tokens.getOrNull(1)?.let { if (cache.remove(it)) "1" else "0" }
            "SIZE" -> cache.size.toString()
            else -> null
        }
        if (result != null) {
            writer.write(result)
            writer.write('\n'.code)
        }
    }
    writer.flush()
}

private fun ByteArray.indexOfFirst(from: Int, target: Byte): Int {
    for (i in from until size) if (this[i] == target) return i
    return size
}

fun main() {
    val input = System.`in`.readBytes()
    BufferedOutputStream(System.out, 1 shl 16).use { run(input, it) }
    exitProcess(0)
}
