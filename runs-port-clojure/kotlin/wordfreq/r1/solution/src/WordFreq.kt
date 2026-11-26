// Prints the ten most frequent ASCII words read from standard input.
package wordfreq

import java.io.BufferedOutputStream
import java.io.InputStream

private const val TOP_N = 10
private const val BUFFER_SIZE = 1 shl 16

/** Mutable counter stored as a map value so increments avoid re-hashing and boxing. */
private class Counter(var count: Long = 0)

/**
 * Streams [input] and counts lowercased words, where a word is a maximal run of
 * ASCII letters. Every other byte is a separator.
 */
fun countWords(input: InputStream): Map<String, Long> {
    val counts = HashMap<String, Counter>()
    val chunk = ByteArray(BUFFER_SIZE)
    var word = ByteArray(64)
    var len = 0

    fun flush() {
        if (len > 0) {
            val key = String(word, 0, len, Charsets.ISO_8859_1)
            counts.getOrPut(key) { Counter() }.count++
            len = 0
        }
    }

    while (true) {
        val read = input.read(chunk)
        if (read < 0) break
        for (i in 0 until read) {
            val b = chunk[i].toInt()
            val lower = when (b) {
                in 'a'.code..'z'.code -> b
                in 'A'.code..'Z'.code -> b + ('a' - 'A')
                else -> {
                    flush()
                    continue
                }
            }
            if (len == word.size) word = word.copyOf(len * 2)
            word[len++] = lower.toByte()
        }
    }
    flush()

    return counts.mapValues { it.value.count }
}

/** Returns up to [n] (word, count) pairs ordered by count descending, then word ascending. */
fun topWords(counts: Map<String, Long>, n: Int): List<Pair<String, Long>> =
    counts.entries
        .sortedWith(compareByDescending<Map.Entry<String, Long>> { it.value }.thenBy { it.key })
        .take(n)
        .map { it.key to it.value }

fun main() {
    val top = topWords(countWords(System.`in`), TOP_N)
    val text = buildString {
        for ((word, count) in top) append(count).append(' ').append(word).append('\n')
    }
    BufferedOutputStream(System.out).use { it.write(text.toByteArray(Charsets.US_ASCII)) }
}
