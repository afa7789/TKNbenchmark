import java.io.BufferedOutputStream
import java.io.InputStream
import java.io.OutputStream

/**
 * Fixed-capacity LRU cache. Backed by an access-ordered [LinkedHashMap], so lookups,
 * insertions, refreshes and evictions all run in O(1) expected time.
 */
class LruCache<K, V>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive, was $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(initialCapacityFor(capacity), 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Returns the value for [key] and marks it most recently used, or null on a miss. */
    operator fun get(key: K): V? = entries[key]

    /** Inserts or overwrites [key], marks it most recently used and evicts the LRU entry if over capacity. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key]; returns true if it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null

    private companion object {
        // Pre-size modestly: the full capacity may never be reached.
        fun initialCapacityFor(capacity: Int): Int = minOf(capacity, 1 shl 16) * 4 / 3 + 1
    }
}

/** Runs the command script in [input] (capacity line followed by commands) and writes results to [output]. */
fun runSimulation(input: String, output: OutputStream) {
    val out = StringBuilder()
    var pos = 0
    var lineNo = 0
    var cache: LruCache<String, String>? = null

    while (pos <= input.length) {
        var end = input.indexOf('\n', pos)
        if (end == -1) end = input.length
        val lineEnd = if (end > pos && input[end - 1] == '\r') end - 1 else end
        val line = input.substring(pos, lineEnd)
        pos = end + 1

        if (lineNo++ == 0) {
            cache = LruCache(parseCapacity(line))
            continue
        }
        if (line.isEmpty()) continue
        execute(checkNotNull(cache), line, out)
    }

    output.write(out.toString().toByteArray(Charsets.ISO_8859_1))
}

private fun execute(cache: LruCache<String, String>, line: String, out: StringBuilder) {
    val sp1 = line.indexOf(' ')
    val command = if (sp1 == -1) line else line.substring(0, sp1)
    when (command) {
        "SET" -> {
            val sp2 = line.indexOf(' ', sp1 + 1)
            if (sp2 != -1) cache[line.substring(sp1 + 1, sp2)] = line.substring(sp2 + 1)
        }
        "GET" -> if (sp1 != -1) out.append(cache[line.substring(sp1 + 1)] ?: "NULL").append('\n')
        "DEL" -> if (sp1 != -1) out.append(if (cache.remove(line.substring(sp1 + 1))) '1' else '0').append('\n')
        "SIZE" -> out.append(cache.size).append('\n')
    }
}

private fun parseCapacity(line: String): Int =
    line.trim().takeWhile { it.isDigit() }.toIntOrNull()?.coerceAtLeast(1) ?: 1

private fun InputStream.readLatin1(): String = String(readBytes(), Charsets.ISO_8859_1)

fun main() {
    val input = System.`in`.readLatin1()
    BufferedOutputStream(System.out, 1 shl 16).use { runSimulation(input, it) }
}
