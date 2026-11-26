// Print the 10 most frequent ASCII words read from standard input.
package wordfreq

import java.io.BufferedOutputStream
import kotlin.system.exitProcess

const val TOP_N = 10

/** Mutable counter so the map avoids re-boxing an Int on every increment. */
private class Count {
    var value = 0
}

private fun isAsciiLetter(b: Int): Boolean = (b or 0x20) in 'a'.code..'z'.code

/**
 * Count words (maximal runs of ASCII letters, folded to lowercase) in [data].
 * Every other byte is a separator.
 */
fun countWords(data: ByteArray): Map<String, Int> {
    val counts = HashMap<String, Count>()
    var i = 0
    val n = data.size
    while (i < n) {
        if (!isAsciiLetter(data[i].toInt())) {
            i++
            continue
        }
        val start = i
        while (i < n && isAsciiLetter(data[i].toInt())) {
            data[i] = (data[i].toInt() or 0x20).toByte()
            i++
        }
        val word = String(data, start, i - start, Charsets.ISO_8859_1)
        counts.getOrPut(word, ::Count).value++
    }
    return counts.mapValues { it.value.value }
}

/** Return up to [n] (word, count) pairs, by count descending then word ascending. */
fun topWords(data: ByteArray, n: Int = TOP_N): List<Pair<String, Int>> =
    countWords(data).entries
        .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
        .take(n)
        .map { it.key to it.value }

fun main() {
    val data = System.`in`.readAllBytes()
    val report = buildString {
        for ((word, count) in topWords(data)) append(count).append(' ').append(word).append('\n')
    }
    BufferedOutputStream(System.out).use { it.write(report.toByteArray(Charsets.ISO_8859_1)) }
    exitProcess(0)
}
