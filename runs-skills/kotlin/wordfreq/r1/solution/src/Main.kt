import java.io.BufferedOutputStream

private const val TOP_N = 10

/** A distinct word and the number of times it occurred. */
data class WordCount(val word: String, val count: Int)

/**
 * Counts words stored as byte ranges of a shared, already lowercased buffer.
 * Open addressing with linear probing avoids allocating a String per occurrence.
 */
class WordCounter(private val text: ByteArray) {
    private var capacity = 1 shl 12
    private var starts = IntArray(capacity)
    private var lengths = IntArray(capacity) // 0 marks an empty slot
    private var hashes = IntArray(capacity)
    private var counts = IntArray(capacity)
    private var size = 0

    fun add(start: Int, length: Int, hash: Int) {
        var slot = hash and (capacity - 1)
        while (true) {
            val len = lengths[slot]
            if (len == 0) {
                starts[slot] = start
                lengths[slot] = length
                hashes[slot] = hash
                counts[slot] = 1
                if (++size * 2 > capacity) grow()
                return
            }
            if (len == length && hashes[slot] == hash && sameBytes(starts[slot], start, length)) {
                counts[slot]++
                return
            }
            slot = (slot + 1) and (capacity - 1)
        }
    }

    private fun sameBytes(a: Int, b: Int, length: Int): Boolean =
        java.util.Arrays.equals(text, a, a + length, text, b, b + length)

    private fun grow() {
        val oldStarts = starts
        val oldLengths = lengths
        val oldHashes = hashes
        val oldCounts = counts
        capacity = capacity shl 1
        starts = IntArray(capacity)
        lengths = IntArray(capacity)
        hashes = IntArray(capacity)
        counts = IntArray(capacity)
        val mask = capacity - 1
        for (i in oldLengths.indices) {
            if (oldLengths[i] == 0) continue
            var slot = oldHashes[i] and mask
            while (lengths[slot] != 0) slot = (slot + 1) and mask
            starts[slot] = oldStarts[i]
            lengths[slot] = oldLengths[i]
            hashes[slot] = oldHashes[i]
            counts[slot] = oldCounts[i]
        }
    }

    /** The [n] most frequent words, by count descending then word ascending. */
    fun top(n: Int): List<WordCount> {
        val order = compareByDescending<WordCount> { it.count }.thenBy { it.word }
        val best = java.util.PriorityQueue(order.reversed())
        for (i in 0..<capacity) {
            val len = lengths[i]
            if (len == 0) continue
            if (best.size == n && counts[i] < best.peek().count) continue
            best.add(WordCount(String(text, starts[i], len, Charsets.ISO_8859_1), counts[i]))
            if (best.size > n) best.poll()
        }
        return best.sortedWith(order)
    }
}

/** Lowercases ASCII letters in place and counts every maximal run of them. */
fun countWords(text: ByteArray): WordCounter {
    val counter = WordCounter(text)
    var start = -1
    var hash = 0
    for (i in text.indices) {
        val b = text[i].toInt()
        val lower = b or 0x20
        if (lower in 'a'.code..'z'.code) {
            text[i] = lower.toByte()
            if (start < 0) {
                start = i
                hash = 0
            }
            hash = 31 * hash + lower
        } else if (start >= 0) {
            counter.add(start, i - start, mix(hash))
            start = -1
        }
    }
    if (start >= 0) counter.add(start, text.size - start, mix(hash))
    return counter
}

private fun mix(h: Int): Int {
    val x = h * -0x61c88647
    return x xor (x ushr 16)
}

fun main() {
    val input = System.`in`.readAllBytes()
    val output = buildString {
        for ((word, count) in countWords(input).top(TOP_N)) append(count).append(' ').append(word).append('\n')
    }
    BufferedOutputStream(System.out).use { it.write(output.toByteArray(Charsets.ISO_8859_1)) }
}
