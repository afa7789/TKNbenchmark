// wordfreq: print the 10 most frequent ASCII words read from standard input.

import java.io.InputStream
import java.io.PrintStream

private const val TOP_N = 10
private const val CHUNK_SIZE = 1 shl 16

private class Counter(var value: Long = 0)

private fun isAsciiLetter(b: Int): Boolean = b in 'A'.code..'Z'.code || b in 'a'.code..'z'.code

private fun toLowerAscii(b: Int): Int = if (b in 'A'.code..'Z'.code) b + ('a' - 'A') else b

/** Growable byte buffer holding the word currently being scanned. */
private class WordBuffer {
    private var bytes = ByteArray(64)
    var length = 0
        private set

    fun append(b: Int) {
        if (length == bytes.size) bytes = bytes.copyOf(bytes.size * 2)
        bytes[length++] = b.toByte()
    }

    fun isNotEmpty(): Boolean = length > 0

    fun clear() {
        length = 0
    }

    override fun toString(): String = String(bytes, 0, length, Charsets.ISO_8859_1)
}

/**
 * Streams [input], accumulating lowercase words. A word may straddle chunk
 * boundaries, so the in-progress word is carried across reads.
 */
private fun countWords(input: InputStream): Map<String, Counter> {
    val counts = HashMap<String, Counter>()
    val buffer = ByteArray(CHUNK_SIZE)
    val current = WordBuffer()

    fun flushWord() {
        counts.getOrPut(current.toString()) { Counter() }.value++
        current.clear()
    }

    while (true) {
        val n = input.read(buffer)
        if (n < 0) break
        for (i in 0 until n) {
            val c = buffer[i].toInt() and 0xFF
            if (isAsciiLetter(c)) {
                current.append(toLowerAscii(c))
            } else if (current.isNotEmpty()) {
                flushWord()
            }
        }
    }
    if (current.isNotEmpty()) flushWord()
    return counts
}

private val byRank: Comparator<Pair<String, Long>> =
    compareByDescending<Pair<String, Long>> { it.second }.thenBy { it.first }

private fun topWords(counts: Map<String, Counter>, limit: Int): List<Pair<String, Long>> =
    counts.entries
        .map { (word, counter) -> word to counter.value }
        .sortedWith(byRank)
        .take(limit)

fun main() {
    val counts = countWords(System.`in`)
    val out = PrintStream(System.out.buffered(), false, Charsets.ISO_8859_1)
    for ((word, count) in topWords(counts, TOP_N)) {
        out.print(count)
        out.print(' ')
        out.print(word)
        out.print('\n')
    }
    out.flush()
}
