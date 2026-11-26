/** Simulate an LRU cache driven by commands read from standard input. */

import java.io.BufferedOutputStream

private const val NULL = "NULL"

/** A fixed-capacity cache that evicts its least recently used key on overflow. */
class LruCache(private val capacity: Int) {
    private val map = object : LinkedHashMap<String, String>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>): Boolean =
            size > capacity
    }

    val size: Int get() = map.size

    /** Returns the value for [key], marking it most recently used, or null on a miss. */
    operator fun get(key: String): String? = map[key]

    /** Inserts or overwrites [key], marking it most recently used. */
    operator fun set(key: String, value: String) {
        map[key] = value
    }

    /** Removes [key]; returns whether it was present. */
    fun remove(key: String): Boolean = map.remove(key) != null
}

private fun Byte.isAsciiWhitespace(): Boolean {
    val c = toInt()
    return c == ' '.code || c in 0x09..0x0D
}

/** Splits `data[start, end)` on ASCII whitespace into at most [limit] tokens (latin-1 decoded). */
private fun tokenize(data: ByteArray, start: Int, end: Int, limit: Int): List<String> {
    val tokens = ArrayList<String>(limit)
    var i = start
    while (i < end && tokens.size < limit) {
        while (i < end && data[i].isAsciiWhitespace()) i++
        if (i >= end) break
        val from = i
        while (i < end && !data[i].isAsciiWhitespace()) i++
        tokens += String(data, from, i - from, Charsets.ISO_8859_1)
    }
    return tokens
}

/** Executes the command stream in [data] and returns the output bytes. */
fun run(data: ByteArray): ByteArray {
    var lineEnd = data.indexOf('\n'.code.toByte()).let { if (it < 0) data.size else it }
    val header = String(data, 0, lineEnd, Charsets.ISO_8859_1).trim { it.code == 32 || it.code in 9..13 }
    if (header.isEmpty()) return ByteArray(0)
    val cache = LruCache(header.replace("_", "").toInt())

    val out = StringBuilder()
    fun emit(s: String) {
        out.append(s).append('\n')
    }

    var pos = lineEnd + 1
    while (pos <= data.size) {
        lineEnd = pos
        while (lineEnd < data.size && data[lineEnd] != '\n'.code.toByte()) lineEnd++
        val parts = tokenize(data, pos, lineEnd, 3)
        pos = lineEnd + 1
        if (parts.isEmpty()) continue
        when (parts[0]) {
            "GET" -> emit(cache[parts[1]] ?: NULL)
            "SET" -> cache[parts[1]] = parts[2]
            "DEL" -> emit(if (cache.remove(parts[1])) "1" else "0")
            "SIZE" -> emit(cache.size.toString())
        }
    }
    return out.toString().toByteArray(Charsets.ISO_8859_1)
}

fun main() {
    val result = run(System.`in`.readBytes())
    BufferedOutputStream(System.out).use { it.write(result) }
}
