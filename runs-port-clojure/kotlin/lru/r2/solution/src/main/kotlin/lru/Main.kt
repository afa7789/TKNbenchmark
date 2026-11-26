package lru

import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter

/** Upper bound on the initial table size, so huge capacities don't pre-allocate eagerly. */
private const val MAX_INITIAL_CAPACITY = 1 shl 20

/**
 * A fixed-capacity cache that evicts the least recently used entry on overflow.
 * Backed by an access-ordered [LinkedHashMap], so every operation is O(1) expected.
 */
class LruCache<K : Any, V : Any>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive, was $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(
        minOf(capacity + 1, MAX_INITIAL_CAPACITY), 0.75f, true,
    ) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    operator fun get(key: K): V? = entries[key]

    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key], returning whether it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null
}

/** Executes one command line against [cache], writing any output to [out]. */
private fun execute(cache: LruCache<String, String>, line: String, out: BufferedWriter) {
    val sp1 = line.indexOf(' ')
    val command = if (sp1 < 0) line else line.substring(0, sp1)
    val args = if (sp1 < 0) "" else line.substring(sp1 + 1)

    fun emit(s: String) {
        out.write(s)
        out.write('\n'.code)
    }

    when (command) {
        "SET" -> {
            val sp2 = args.indexOf(' ')
            if (sp2 >= 0) cache[args.substring(0, sp2)] = args.substring(sp2 + 1)
        }
        "GET" -> emit(cache[args] ?: "NULL")
        "DEL" -> emit(if (cache.remove(args)) "1" else "0")
        "SIZE" -> emit(cache.size.toString())
    }
}

/** Reads the capacity and command stream from [input], writing results to [out]. */
fun run(input: BufferedReader, out: BufferedWriter) {
    val firstLine = input.readLine() ?: return
    val cache = LruCache<String, String>(firstLine.trim().toInt())
    input.lineSequence()
        .map(String::trim)
        .filter(String::isNotEmpty)
        .forEach { execute(cache, it, out) }
    out.flush()
}

fun main() {
    val input = BufferedReader(InputStreamReader(System.`in`, Charsets.US_ASCII), 1 shl 16)
    val out = BufferedWriter(OutputStreamWriter(System.out, Charsets.US_ASCII), 1 shl 16)
    run(input, out)
}
