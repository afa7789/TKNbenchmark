package lru

import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.io.Writer
import java.nio.charset.StandardCharsets

/**
 * A fixed-capacity cache that evicts the least-recently-used key.
 *
 * Backed by an access-ordered [LinkedHashMap]: every get/put moves the key to the
 * most-recently-used end, so the eldest entry is always the LRU one.
 */
class LruCache<K : Any, V : Any>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive, was $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(initialCapacityFor(capacity), LOAD_FACTOR, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
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
        const val MAX_INITIAL_CAPACITY = 1 shl 20

        fun initialCapacityFor(capacity: Int): Int = minOf(capacity + 1, MAX_INITIAL_CAPACITY)
    }
}

/** Executes one command line against [cache], writing any output to [out]. */
private fun execute(cache: LruCache<String, String>, line: String, out: Writer) {
    val sp1 = line.indexOf(' ')
    val op = if (sp1 < 0) line else line.substring(0, sp1)
    val arg = if (sp1 < 0) "" else line.substring(sp1 + 1)

    when (op) {
        "SET" -> {
            val sp2 = arg.indexOf(' ')
            if (sp2 >= 0) cache[arg.substring(0, sp2)] = arg.substring(sp2 + 1)
        }
        "GET" -> out.writeLine(cache[arg] ?: "NULL")
        "DEL" -> out.writeLine(if (cache.remove(arg)) "1" else "0")
        "SIZE" -> out.writeLine(cache.size.toString())
    }
}

private fun Writer.writeLine(s: String) {
    write(s)
    write('\n'.code)
}

/** Processes the whole input from [input], writing results to [out]. */
fun run(input: BufferedReader, out: Writer) {
    val header = input.readLine()
    if (header != null) {
        val cache = LruCache<String, String>(header.trim().toInt())
        input.lineSequence()
            .map(String::trim)
            .filter(String::isNotEmpty)
            .forEach { execute(cache, it, out) }
    }
    out.flush()
}

fun main() {
    val charset = StandardCharsets.ISO_8859_1
    val input = BufferedReader(InputStreamReader(System.`in`, charset), BUFFER_SIZE)
    val out = BufferedWriter(OutputStreamWriter(System.out, charset), BUFFER_SIZE)
    run(input, out)
}

private const val BUFFER_SIZE = 1 shl 16
