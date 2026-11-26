// Print the 10 most frequent ASCII words read from standard input.
package wordfreq

import java.io.InputStream
import java.io.OutputStream
import java.util.PriorityQueue

const val TOP_N = 10

private const val BUFFER_SIZE = 1 shl 16

/** Mutable counter, so that incrementing a word does not box a new Int each time. */
private class Count(var value: Int = 0)

/** Ordering by count descending, then word ascending (byte order == char order for ASCII). */
private val byFrequency: Comparator<Pair<String, Int>> =
    compareByDescending<Pair<String, Int>> { it.second }.thenBy { it.first }

private fun isAsciiLetter(b: Int): Boolean = (b or 0x20) in 'a'.code..'z'.code

/** Counts every maximal run of ASCII letters in [input], folded to lowercase. */
fun countWords(input: InputStream): Map<String, Int> {
    val counts = HashMap<String, Count>()
    val chunk = ByteArray(BUFFER_SIZE)
    var word = ByteArray(64)
    var length = 0

    fun flushWord() {
        if (length > 0) {
            val key = String(word, 0, length, Charsets.ISO_8859_1)
            counts.getOrPut(key) { Count() }.value++
            length = 0
        }
    }

    while (true) {
        val read = input.read(chunk)
        if (read < 0) break
        for (i in 0 until read) {
            val b = chunk[i].toInt()
            if (isAsciiLetter(b)) {
                if (length == word.size) word = word.copyOf(word.size * 2)
                word[length++] = (b or 0x20).toByte()
            } else {
                flushWord()
            }
        }
    }
    flushWord()

    return counts.mapValues { it.value.value }
}

/** Returns up to [n] (word, count) pairs, by count descending then word ascending. */
fun topWords(counts: Map<String, Int>, n: Int = TOP_N): List<Pair<String, Int>> {
    if (n <= 0) return emptyList()
    // Bounded heap whose head is the worst of the current best n.
    val heap = PriorityQueue(n + 1, byFrequency.reversed())
    for ((word, count) in counts) {
        val candidate = word to count
        if (heap.size < n) {
            heap.add(candidate)
        } else if (byFrequency.compare(candidate, heap.peek()) < 0) {
            heap.poll()
            heap.add(candidate)
        }
    }
    return heap.sortedWith(byFrequency)
}

fun writeReport(top: List<Pair<String, Int>>, out: OutputStream) {
    val text = buildString {
        for ((word, count) in top) append(count).append(' ').append(word).append('\n')
    }
    out.write(text.toByteArray(Charsets.ISO_8859_1))
    out.flush()
}

fun main() {
    writeReport(topWords(countWords(System.`in`)), System.out)
}
