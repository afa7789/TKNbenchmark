// wordfreq: print the 10 most frequent ASCII-letter words read from stdin.
package wordfreq

import java.io.BufferedOutputStream

private const val TOP_N = 10

/** Mutable occurrence counter, kept boxed once per distinct word to avoid re-boxing on every hit. */
private class Count(var value: Long = 0)

private fun isAsciiLetter(b: Int): Boolean = (b in 'A'.code..'Z'.code) || (b in 'a'.code..'z'.code)

/**
 * Counts maximal runs of ASCII letters in [bytes], case-folded to lowercase.
 * The buffer is lowercased in place, so callers must not rely on its contents afterwards.
 */
internal fun countWords(bytes: ByteArray): Map<String, Long> {
    val counts = HashMap<String, Count>()
    var start = -1
    for (i in 0..bytes.size) {
        val b = if (i < bytes.size) bytes[i].toInt() else -1
        if (b >= 0 && isAsciiLetter(b)) {
            bytes[i] = (b or 0x20).toByte() // ASCII letters only: set the lowercase bit
            if (start < 0) start = i
        } else if (start >= 0) {
            val word = String(bytes, start, i - start, Charsets.ISO_8859_1)
            counts.getOrPut(word) { Count() }.value++
            start = -1
        }
    }
    return counts.mapValues { it.value.value }
}

/** Returns up to [n] entries ordered by count descending, then word ascending. */
internal fun topWords(counts: Map<String, Long>, n: Int): List<Pair<String, Long>> =
    counts.entries
        .sortedWith(compareByDescending<Map.Entry<String, Long>> { it.value }.thenBy { it.key })
        .take(n)
        .map { it.key to it.value }

fun main() {
    val input = System.`in`.readBytes()
    val report = buildString {
        for ((word, count) in topWords(countWords(input), TOP_N)) {
            append(count).append(' ').append(word).append('\n')
        }
    }
    BufferedOutputStream(System.out).use { it.write(report.toByteArray(Charsets.ISO_8859_1)) }
}
