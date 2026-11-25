import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.io.BufferedWriter
import java.io.OutputStreamWriter

/** A fixed-capacity cache that evicts the least recently used key once [capacity] is exceeded. */
class LruCache<K, V>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive, was $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(initialCapacityFor(capacity), LOAD_FACTOR, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    operator fun get(key: K): V? = entries[key]

    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key]; returns true if it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null

    private companion object {
        const val LOAD_FACTOR = 0.75f
        const val MAX_PREALLOCATED = 1 shl 16

        fun initialCapacityFor(capacity: Int): Int = (minOf(capacity, MAX_PREALLOCATED) / LOAD_FACTOR).toInt() + 1
    }
}

fun main() {
    val reader = BufferedReader(InputStreamReader(System.`in`, Charsets.ISO_8859_1), 1 shl 16)
    val out = PrintWriter(BufferedWriter(OutputStreamWriter(System.out, Charsets.ISO_8859_1), 1 shl 16), false)

    val capacity = reader.readLine()?.trim()?.toIntOrNull() ?: return
    val cache = LruCache<String, String>(capacity)

    reader.lineSequence().forEach { raw ->
        val line = raw.trimEnd('\r')
        if (line.isEmpty()) return@forEach
        val parts = line.split(' ')
        when (parts[0]) {
            "SET" -> if (parts.size >= 3) cache[parts[1]] = parts[2]
            "GET" -> if (parts.size >= 2) out.println(cache[parts[1]] ?: "NULL")
            "DEL" -> if (parts.size >= 2) out.println(if (cache.remove(parts[1])) 1 else 0)
            "SIZE" -> out.println(cache.size)
        }
    }
    out.flush()
}
