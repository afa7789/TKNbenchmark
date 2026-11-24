import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintStream
import java.io.BufferedOutputStream
import java.io.FileOutputStream
import java.io.FileDescriptor

/**
 * Fixed-capacity cache that evicts the least recently used entry.
 * Backed by an access-ordered [LinkedHashMap], so every operation is O(1) expected.
 */
class LruCache<K, V>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive, was $capacity" }
    }

    private val map = object : LinkedHashMap<K, V>(initialTableSize(capacity), LOAD_FACTOR, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = map.size

    /** Inserts or overwrites [key]; it becomes the most recently used. */
    operator fun set(key: K, value: V) {
        // Remove first so an overwrite is re-inserted at the most-recent end.
        map.remove(key)
        map[key] = value
    }

    /** Returns the value for [key], marking it most recently used, or null on a miss. */
    operator fun get(key: K): V? = map[key]

    /** Removes [key]; returns true if it was present. */
    fun remove(key: K): Boolean = map.remove(key) != null

    private companion object {
        const val LOAD_FACTOR = 0.75f
        const val MAX_PREALLOCATED = 1 shl 16

        fun initialTableSize(capacity: Int): Int =
            (minOf(capacity, MAX_PREALLOCATED) / LOAD_FACTOR).toInt() + 1
    }
}

private fun runCommand(line: String, cache: LruCache<String, String>, out: StringBuilder) {
    val firstSpace = line.indexOf(' ')
    val command = if (firstSpace < 0) line else line.substring(0, firstSpace)
    when (command) {
        "SET" -> {
            val secondSpace = line.indexOf(' ', firstSpace + 1)
            if (firstSpace < 0 || secondSpace < 0) return
            cache[line.substring(firstSpace + 1, secondSpace)] = line.substring(secondSpace + 1)
        }
        "GET" -> {
            if (firstSpace < 0) return
            out.append(cache[line.substring(firstSpace + 1)] ?: "NULL").append('\n')
        }
        "DEL" -> {
            if (firstSpace < 0) return
            out.append(if (cache.remove(line.substring(firstSpace + 1))) '1' else '0').append('\n')
        }
        "SIZE" -> out.append(cache.size).append('\n')
    }
}

fun main() {
    val reader = BufferedReader(InputStreamReader(System.`in`, Charsets.ISO_8859_1), 1 shl 16)
    val capacity = reader.readLine()?.trim()?.toIntOrNull() ?: return
    val cache = LruCache<String, String>(capacity)

    val stdout = PrintStream(BufferedOutputStream(FileOutputStream(FileDescriptor.out), 1 shl 16), false, Charsets.ISO_8859_1)
    val out = StringBuilder(1 shl 16)
    while (true) {
        val line = reader.readLine()?.trimEnd('\r') ?: break
        if (line.isEmpty()) continue
        runCommand(line, cache, out)
        if (out.length >= FLUSH_THRESHOLD) {
            stdout.append(out)
            out.setLength(0)
        }
    }
    stdout.append(out)
    stdout.flush()
}

private const val FLUSH_THRESHOLD = 1 shl 15
