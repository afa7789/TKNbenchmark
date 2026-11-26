// Prints the 10 most frequent ASCII words read from standard input.
package wordfreq

import java.io.InputStream
import java.io.OutputStream
import kotlin.system.exitProcess

private const val TOP_N = 10
private const val BUFFER_SIZE = 1 shl 16

/** Mutable occurrence counter, avoiding boxing on every increment. */
private class Counter {
    var value: Long = 0
}

/** Returns the lowercase form of an ASCII letter byte, or -1 for any separator byte. */
private fun lowerLetter(b: Int): Int = when (b) {
    in 'a'.code..'z'.code -> b
    in 'A'.code..'Z'.code -> b + ('a'.code - 'A'.code)
    else -> -1
}

/** Reads [input] to exhaustion and returns lowercase word -> occurrence count. */
fun countWords(input: InputStream): Map<String, Long> {
    val counts = HashMap<String, Counter>()
    val buf = ByteArray(BUFFER_SIZE)
    var word = ByteArray(64)
    var len = 0

    fun flushWord() {
        if (len == 0) return
        // Words are pure ASCII, so Latin-1 decoding is an exact byte-to-char mapping.
        val key = String(word, 0, len, Charsets.ISO_8859_1)
        counts.getOrPut(key, ::Counter).value++
        len = 0
    }

    while (true) {
        val n = input.read(buf)
        if (n < 0) break
        for (i in 0 until n) {
            val lc = lowerLetter(buf[i].toInt() and 0xFF)
            if (lc < 0) {
                flushWord()
            } else {
                if (len == word.size) word = word.copyOf(word.size * 2)
                word[len++] = lc.toByte()
            }
        }
    }
    flushWord()

    return counts.mapValues { it.value.value }
}

/** Returns up to [n] (word, count) pairs: count descending, then word ascending. */
fun topWords(counts: Map<String, Long>, n: Int): List<Pair<String, Long>> =
    counts.entries
        .sortedWith(compareByDescending<Map.Entry<String, Long>> { it.value }.thenBy { it.key })
        .take(n)
        .map { it.key to it.value }

private fun writeReport(top: List<Pair<String, Long>>, out: OutputStream) {
    val report = buildString {
        for ((word, count) in top) append(count).append(' ').append(word).append('\n')
    }
    out.write(report.toByteArray(Charsets.ISO_8859_1))
    out.flush()
}

fun main() {
    val input = System.`in`.buffered(BUFFER_SIZE)
    writeReport(topWords(countWords(input), TOP_N), System.out)
    exitProcess(0)
}
