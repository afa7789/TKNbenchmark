/**
 * wordfreq: print the 10 most frequent ASCII words read from standard input.
 *
 * A word is a maximal run of ASCII letters; every other byte is a separator.
 * Words are folded to lowercase and ranked by count descending, then by word
 * ascending (byte order).
 */

import java.io.BufferedOutputStream
import java.io.PrintStream

private const val TOP_N = 10
private const val CASE_BIT = 0x20

/** Mutable counter so incrementing a word does not re-box an Int per occurrence. */
private class Counter {
    var value = 0
}

data class WordCount(val word: String, val count: Int)

/** Ranking order: count descending, then word ascending (ASCII, so UTF-16 order equals byte order). */
private val RANKING: Comparator<WordCount> =
    compareByDescending<WordCount> { it.count }.thenBy { it.word }

private fun Byte.isAsciiLetter(): Boolean {
    val b = toInt()
    return b in 'a'.code..'z'.code || b in 'A'.code..'Z'.code
}

/** Counts lowercase-folded words in [input]. The buffer is lowercased in place. */
fun countWords(input: ByteArray): Map<String, Int> {
    val counts = HashMap<String, Counter>()
    val len = input.size
    var i = 0
    while (i < len) {
        while (i < len && !input[i].isAsciiLetter()) i++
        if (i >= len) break
        val start = i
        while (i < len && input[i].isAsciiLetter()) {
            input[i] = (input[i].toInt() or CASE_BIT).toByte()
            i++
        }
        val word = String(input, start, i - start, Charsets.ISO_8859_1)
        counts.getOrPut(word, ::Counter).value++
    }
    return counts.mapValues { it.value.value }
}

/** Selects the top [n] entries by [RANKING] without sorting the whole map. */
fun topWords(counts: Map<String, Int>, n: Int): List<WordCount> {
    val top = ArrayList<WordCount>(n + 1)
    for ((word, count) in counts) {
        val entry = WordCount(word, count)
        if (top.size == n && RANKING.compare(entry, top.last()) >= 0) continue
        var pos = top.binarySearch(entry, RANKING)
        if (pos < 0) pos = -(pos + 1)
        top.add(pos, entry)
        if (top.size > n) top.removeAt(top.lastIndex)
    }
    return top
}

fun main() {
    val input = System.`in`.readBytes()
    val top = topWords(countWords(input), TOP_N)
    if (top.isEmpty()) return
    PrintStream(BufferedOutputStream(System.out), false, Charsets.US_ASCII).use { out ->
        for ((word, count) in top) out.print("$count $word\n")
    }
}
