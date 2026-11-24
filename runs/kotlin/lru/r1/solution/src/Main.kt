import java.io.BufferedWriter
import java.io.OutputStreamWriter

/**
 * Fixed-capacity LRU cache backed by an access-ordered [LinkedHashMap]:
 * every lookup and insertion moves the entry to the tail, so the head is always
 * the least recently used entry. All operations run in O(1) expected time.
 */
class LruCache<K, V>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive, was $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    operator fun get(key: K): V? = entries[key]

    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key]; returns true if it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null
}

private fun runCommand(line: String, cache: LruCache<String, String>, out: Appendable) {
    val parts = line.split(' ')
    when (parts[0]) {
        "SET" -> if (parts.size >= 3) cache[parts[1]] = parts[2]
        "GET" -> if (parts.size >= 2) out.append(cache[parts[1]] ?: "NULL").append('\n')
        "DEL" -> if (parts.size >= 2) out.append(if (cache.remove(parts[1])) "1" else "0").append('\n')
        "SIZE" -> out.append(cache.size.toString()).append('\n')
    }
}

fun main() {
    val lines = System.`in`.bufferedReader(Charsets.ISO_8859_1).lineSequence()
        .map { it.trimEnd('\r') }
        .iterator()
    if (!lines.hasNext()) return
    val capacity = lines.next().trim().toInt()
    val cache = LruCache<String, String>(capacity)

    BufferedWriter(OutputStreamWriter(System.out, Charsets.ISO_8859_1), 1 shl 16).use { out ->
        for (line in lines) {
            if (line.isNotEmpty()) runCommand(line, cache, out)
        }
    }
}
