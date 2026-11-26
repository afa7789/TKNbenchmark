/** Print the 10 most frequent ASCII words read from standard input. */
package wordfreq

import java.io.InputStream
import java.io.PrintStream
import kotlin.system.exitProcess

private const val TOP_N = 10
private const val CHUNK_SIZE = 1 shl 20

/** Mutable occurrence count, boxed once per distinct word to avoid re-boxing on every hit. */
private class Counter(var value: Int = 0)

/**
 * Counts maximal runs of ASCII letters, case-folded to lowercase.
 * Every other byte is a separator; words may span chunk boundaries.
 */
class WordCounter {
    private val counts = HashMap<String, Counter>()
    private var word = ByteArray(64)
    private var length = 0

    fun feed(bytes: ByteArray, size: Int = bytes.size) {
        for (i in 0 until size) {
            val b = bytes[i].toInt()
            val lower = b or 0x20
            if (lower in 'a'.code..'z'.code) {
                if (length == word.size) word = word.copyOf(word.size * 2)
                word[length++] = lower.toByte()
            } else {
                flush()
            }
        }
    }

    fun feed(stream: InputStream) {
        val buffer = ByteArray(CHUNK_SIZE)
        while (true) {
            val read = stream.read(buffer)
            if (read < 0) break
            feed(buffer, read)
        }
        flush()
    }

    /** Returns the [n] most frequent words: count descending, then word ascending. */
    fun top(n: Int = TOP_N): List<Pair<String, Int>> {
        flush()
        return counts.entries
            .asSequence()
            .map { it.key to it.value.value }
            .sortedWith(compareByDescending<Pair<String, Int>> { it.second }.thenBy { it.first })
            .take(n)
            .toList()
    }

    private fun flush() {
        if (length == 0) return
        // Words are pure ASCII, so Latin-1 decoding is exact and keeps byte ordering.
        val key = String(word, 0, length, Charsets.ISO_8859_1)
        counts.getOrPut(key) { Counter() }.value++
        length = 0
    }
}

fun main() {
    val counter = WordCounter()
    counter.feed(System.`in`)
    val out = buildString {
        for ((word, count) in counter.top()) append(count).append(' ').append(word).append('\n')
    }
    PrintStream(System.out, false, Charsets.ISO_8859_1).apply {
        print(out)
        flush()
    }
    exitProcess(0)
}
