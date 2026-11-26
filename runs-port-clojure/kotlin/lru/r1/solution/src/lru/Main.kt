package lru

import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import kotlin.system.exitProcess

private const val IO_BUFFER_SIZE = 1 shl 20
private const val MAX_INITIAL_CAPACITY = 1 shl 20

/**
 * A fixed-capacity LRU cache backed by an access-ordered [LinkedHashMap]:
 * every lookup or insert moves the key to the most-recently-used end, so the
 * eldest entry is always the least recently used one.
 */
class LruCache(private val capacity: Int) {
    private val entries = object : LinkedHashMap<String, String>(
        minOf(capacity + 1, MAX_INITIAL_CAPACITY), 0.75f, true,
    ) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>): Boolean =
            size > this@LruCache.capacity
    }

    val size: Int get() = entries.size

    operator fun get(key: String): String? = entries[key]

    operator fun set(key: String, value: String) {
        entries[key] = value
    }

    /** Removes [key], returning whether it was present. */
    fun remove(key: String): Boolean = entries.remove(key) != null
}

/** Runs one command line against [cache], writing any output to [out]. */
private fun execute(cache: LruCache, line: String, out: BufferedWriter) {
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

/** Processes the whole input from [input], writing results to [out]. */
fun run(input: BufferedReader, out: BufferedWriter) {
    val firstLine = input.readLine() ?: return
    val cache = LruCache(firstLine.trim().toInt())
    input.lineSequence()
        .map { it.removeSuffix("\r") }
        .filter { it.isNotEmpty() }
        .forEach { execute(cache, it, out) }
}

fun main() {
    val input = BufferedReader(InputStreamReader(System.`in`, Charsets.US_ASCII), IO_BUFFER_SIZE)
    val out = BufferedWriter(OutputStreamWriter(System.out, Charsets.US_ASCII), IO_BUFFER_SIZE)
    out.use { run(input, it) }
    exitProcess(0)
}
