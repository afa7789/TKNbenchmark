/**
 * wordfreq: read stdin, print the 10 most frequent ASCII-letter words.
 */

import java.io.InputStream
import java.io.PrintStream

private const val TOP_N = 10
private const val CHUNK_SIZE = 1 shl 16
private const val CASE_BIT = 0x20

/** Returns the lowercase ASCII letter code for [byte], or -1 if it is not a letter. */
private fun foldLetter(byte: Int): Int {
    val lower = byte or CASE_BIT
    return if (lower in 'a'.code..'z'.code) lower else -1
}

/** Mutable occurrence count, boxed once per distinct word to avoid re-boxing on every hit. */
private class Count(var value: Int = 0)

/** Incrementally tokenizes byte chunks into lowercase words and counts them. */
class WordCounter {
    private val counts = HashMap<String, Count>()

    /** Lowercased bytes of the word currently being read; may span chunk boundaries. */
    private var word = ByteArray(64)
    private var wordLength = 0

    fun feed(chunk: ByteArray, length: Int = chunk.size) {
        for (i in 0 until length) {
            val lower = foldLetter(chunk[i].toInt() and 0xff)
            if (lower >= 0) {
                append(lower.toByte())
            } else if (wordLength > 0) {
                flushWord()
            }
        }
    }

    /** Ends the input and returns the word counts. */
    fun finish(): Map<String, Int> {
        if (wordLength > 0) flushWord()
        return counts.mapValues { it.value.value }
    }

    private fun append(byte: Byte) {
        if (wordLength == word.size) word = word.copyOf(word.size * 2)
        word[wordLength++] = byte
    }

    private fun flushWord() {
        val key = String(word, 0, wordLength, Charsets.ISO_8859_1)
        counts.getOrPut(key, ::Count).value++
        wordLength = 0
    }
}

/** Count descending, then word ascending; words are pure ASCII, so char order equals byte order. */
private val entryOrder: Comparator<Map.Entry<String, Int>> =
    compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }

/** Selects the top [n] entries without sorting the entire map. */
fun topEntries(counts: Map<String, Int>, n: Int): List<Map.Entry<String, Int>> {
    val top = ArrayList<Map.Entry<String, Int>>(n + 1)
    for (entry in counts.entries) {
        if (top.size == n && entryOrder.compare(entry, top.last()) >= 0) continue
        var pos = top.size
        while (pos > 0 && entryOrder.compare(entry, top[pos - 1]) < 0) pos--
        top.add(pos, entry)
        if (top.size > n) top.removeAt(top.lastIndex)
    }
    return top
}

fun countWords(input: InputStream): Map<String, Int> {
    val counter = WordCounter()
    val buffer = ByteArray(CHUNK_SIZE)
    while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        counter.feed(buffer, read)
    }
    return counter.finish()
}

fun main() {
    val report = buildString {
        for ((word, count) in topEntries(countWords(System.`in`), TOP_N)) {
            append(count).append(' ').append(word).append('\n')
        }
    }
    PrintStream(System.out, false, Charsets.US_ASCII).run {
        print(report)
        flush()
    }
}
