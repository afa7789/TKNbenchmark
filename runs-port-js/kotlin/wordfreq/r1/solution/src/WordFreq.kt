// wordfreq: print the 10 most frequent ASCII words read from stdin.
package wordfreq

import java.io.InputStream
import java.io.OutputStream

private const val TOP_N = 10
private const val CHUNK_SIZE = 1 shl 16

/** Mutable counter boxed once per distinct word, so increments don't reallocate. */
private class Counter(var value: Int = 0)

/**
 * Streaming word counter over raw bytes. A word is a maximal run of ASCII letters,
 * folded to lowercase; every other byte is a separator. Words may straddle chunks.
 */
class WordCounter {
    private val counts = HashMap<String, Counter>()
    private var word = ByteArray(64)
    private var length = 0

    fun push(chunk: ByteArray, size: Int = chunk.size) {
        for (i in 0 until size) {
            val b = chunk[i].toInt()
            val folded = b or 0x20
            if (folded in 'a'.code..'z'.code) append(folded.toByte()) else flush()
        }
    }

    fun finish(): Map<String, Int> {
        flush()
        return counts.mapValues { it.value.value }
    }

    private fun append(b: Byte) {
        if (length == word.size) word = word.copyOf(word.size * 2)
        word[length++] = b
    }

    private fun flush() {
        if (length == 0) return
        val key = String(word, 0, length, Charsets.ISO_8859_1)
        counts.getOrPut(key) { Counter() }.value++
        length = 0
    }
}

/** The [n] most frequent words: count descending, then word ascending (byte order). */
fun topWords(counts: Map<String, Int>, n: Int): List<Pair<String, Int>> =
    counts.entries
        .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
        .take(n)
        .map { it.key to it.value }

fun countWords(input: InputStream): Map<String, Int> {
    val counter = WordCounter()
    val buffer = ByteArray(CHUNK_SIZE)
    while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        counter.push(buffer, read)
    }
    return counter.finish()
}

fun writeReport(top: List<Pair<String, Int>>, output: OutputStream) {
    val text = buildString {
        for ((word, count) in top) append(count).append(' ').append(word).append('\n')
    }
    output.write(text.toByteArray(Charsets.ISO_8859_1))
    output.flush()
}

fun main() {
    writeReport(topWords(countWords(System.`in`), TOP_N), System.out)
}
