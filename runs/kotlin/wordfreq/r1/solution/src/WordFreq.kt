import java.io.BufferedOutputStream

/**
 * Counts word frequencies, where a word is a maximal run of ASCII letters folded to lowercase.
 *
 * Words are referenced as (offset, length) slices of the input buffer, which is lowercased in place,
 * so no per-word allocation happens during counting.
 */
private class WordCounter(private val text: ByteArray) {
    private var capacity = 1 shl 12
    private var mask = capacity - 1
    private var offsets = IntArray(capacity)
    private var lengths = IntArray(capacity) // 0 marks an empty slot; words are never empty
    private var hashes = IntArray(capacity)
    private var counts = IntArray(capacity)
    var size = 0
        private set

    fun add(start: Int, length: Int, hash: Int) {
        var slot = hash and mask
        while (true) {
            val len = lengths[slot]
            if (len == 0) {
                offsets[slot] = start
                lengths[slot] = length
                hashes[slot] = hash
                counts[slot] = 1
                if (++size * 2 > capacity) grow()
                return
            }
            if (len == length && hashes[slot] == hash && regionEquals(offsets[slot], start, length)) {
                counts[slot]++
                return
            }
            slot = (slot + 1) and mask
        }
    }

    private fun regionEquals(a: Int, b: Int, length: Int): Boolean =
        java.util.Arrays.equals(text, a, a + length, text, b, b + length)

    private fun grow() {
        val oldOffsets = offsets
        val oldLengths = lengths
        val oldHashes = hashes
        val oldCounts = counts
        capacity = capacity shl 1
        mask = capacity - 1
        offsets = IntArray(capacity)
        lengths = IntArray(capacity)
        hashes = IntArray(capacity)
        counts = IntArray(capacity)
        for (i in oldLengths.indices) {
            if (oldLengths[i] == 0) continue
            var slot = oldHashes[i] and mask
            while (lengths[slot] != 0) slot = (slot + 1) and mask
            offsets[slot] = oldOffsets[i]
            lengths[slot] = oldLengths[i]
            hashes[slot] = oldHashes[i]
            counts[slot] = oldCounts[i]
        }
    }

    /** Returns up to [limit] entries ordered by count descending, then word ascending (byte order). */
    fun top(limit: Int): List<WordCount> =
        lengths.indices
            .filter { lengths[it] != 0 }
            .map { WordCount(String(text, offsets[it], lengths[it], Charsets.US_ASCII), counts[it]) }
            .sortedWith(compareByDescending<WordCount> { it.count }.thenBy { it.word })
            .take(limit)
}

private data class WordCount(val word: String, val count: Int)

private fun mix(h: Int): Int {
    val x = h * -0x61c88647
    return x xor (x ushr 16)
}

private fun countWords(text: ByteArray): WordCounter {
    val counter = WordCounter(text)
    var i = 0
    val n = text.size
    while (i < n) {
        val b = text[i].toInt()
        val lower = b or 0x20
        if (lower !in 'a'.code..'z'.code) {
            i++
            continue
        }
        val start = i
        var hash = 0
        while (i < n) {
            val c = text[i].toInt() or 0x20
            if (c !in 'a'.code..'z'.code) break
            text[i] = c.toByte()
            hash = 31 * hash + c
            i++
        }
        counter.add(start, i - start, mix(hash))
    }
    return counter
}

fun main() {
    val input = System.`in`.readBytes()
    val result = countWords(input).top(10)
    val out = BufferedOutputStream(System.out)
    val sb = StringBuilder()
    for ((word, count) in result) sb.append(count).append(' ').append(word).append('\n')
    out.write(sb.toString().toByteArray(Charsets.US_ASCII))
    out.flush()
}
