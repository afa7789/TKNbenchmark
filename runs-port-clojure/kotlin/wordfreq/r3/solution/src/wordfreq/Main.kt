package wordfreq

import java.io.InputStream
import java.nio.charset.StandardCharsets

private const val TOP_N = 10
private const val BUFFER_SIZE = 64 * 1024

/** Mutable counter so incrementing does not re-box or re-hash. */
private class Counter(var value: Long = 0)

/** Returns the lowercase ASCII byte for a letter, or -1 for any separator. */
private fun lowerAsciiLetter(b: Int): Int = when (b) {
    in 'a'.code..'z'.code -> b
    in 'A'.code..'Z'.code -> b + ('a'.code - 'A'.code)
    else -> -1
}

/** Streams [input], returning lowercase word -> occurrence count. */
fun countWords(input: InputStream): Map<String, Long> {
    val counts = HashMap<String, Counter>()
    val buf = ByteArray(BUFFER_SIZE)
    var word = ByteArray(64)
    var len = 0

    fun flushWord() {
        if (len > 0) {
            val key = String(word, 0, len, StandardCharsets.ISO_8859_1)
            counts.getOrPut(key) { Counter() }.value++
            len = 0
        }
    }

    while (true) {
        val n = input.read(buf)
        if (n < 0) break
        for (i in 0 until n) {
            val c = lowerAsciiLetter(buf[i].toInt() and 0xff)
            if (c < 0) {
                flushWord()
            } else {
                if (len == word.size) word = word.copyOf(word.size * 2)
                word[len++] = c.toByte()
            }
        }
    }
    flushWord()
    return counts.mapValues { it.value.value }
}

/** Returns up to [n] (word, count) pairs, most frequent first, ties by word ascending. */
fun topWords(counts: Map<String, Long>, n: Int): List<Pair<String, Long>> =
    counts.entries
        .sortedWith(compareByDescending<Map.Entry<String, Long>> { it.value }.thenBy { it.key })
        .take(n)
        .map { it.key to it.value }

fun main() {
    val top = topWords(countWords(System.`in`.buffered(BUFFER_SIZE)), TOP_N)
    val out = System.out.bufferedWriter(StandardCharsets.ISO_8859_1)
    out.use {
        for ((word, count) in top) {
            it.write("$count $word\n")
        }
    }
}
