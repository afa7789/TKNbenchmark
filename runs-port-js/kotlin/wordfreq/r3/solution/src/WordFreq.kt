// wordfreq: read stdin, print the 10 most frequent ASCII-letter words.
package wordfreq

import java.io.BufferedOutputStream

private const val TOP_N = 10

/** Lookup table: 0 for separators, otherwise the lowercase ASCII byte. */
private val LOWER = ByteArray(256).also { table ->
    for (c in 'A'.code..'Z'.code) table[c] = (c or 0x20).toByte()
    for (c in 'a'.code..'z'.code) table[c] = c.toByte()
}

/** A distinct word and how many times it occurred. */
data class WordCount(val word: String, val count: Int)

/**
 * Counts words in [text], lowercasing letters in place.
 *
 * Words are stored as (offset, length) references into the buffer itself, keyed in an
 * open-addressing hash table, so no per-occurrence objects are allocated.
 */
class WordCounter(private val text: ByteArray) {
    private var capacity = 1 shl 12
    private var offsets = IntArray(capacity)
    private var lengths = IntArray(capacity) // 0 marks an empty slot
    private var hashes = IntArray(capacity)
    private var counts = IntArray(capacity)
    private var size = 0

    fun count(): WordCounter {
        var start = -1
        var hash = 0
        for (i in text.indices) {
            val lower = LOWER[text[i].toInt() and 0xFF]
            if (lower.toInt() != 0) {
                text[i] = lower
                if (start < 0) {
                    start = i
                    hash = 0
                }
                hash = hash * 31 + lower
            } else if (start >= 0) {
                add(start, i - start, hash)
                start = -1
            }
        }
        if (start >= 0) add(start, text.size - start, hash)
        return this
    }

    private fun add(offset: Int, length: Int, hash: Int) {
        val mask = capacity - 1
        var slot = mix(hash) and mask
        while (lengths[slot] != 0) {
            if (hashes[slot] == hash && matches(offsets[slot], lengths[slot], offset, length)) {
                counts[slot]++
                return
            }
            slot = (slot + 1) and mask
        }
        offsets[slot] = offset
        lengths[slot] = length
        hashes[slot] = hash
        counts[slot] = 1
        if (++size * 2 > capacity) grow()
    }

    private fun matches(aOffset: Int, aLength: Int, bOffset: Int, bLength: Int): Boolean =
        aLength == bLength &&
            java.util.Arrays.equals(text, aOffset, aOffset + aLength, text, bOffset, bOffset + bLength)

    private fun grow() {
        val oldOffsets = offsets
        val oldLengths = lengths
        val oldHashes = hashes
        val oldCounts = counts
        capacity = capacity shl 1
        offsets = IntArray(capacity)
        lengths = IntArray(capacity)
        hashes = IntArray(capacity)
        counts = IntArray(capacity)
        val mask = capacity - 1
        for (old in oldLengths.indices) {
            if (oldLengths[old] == 0) continue
            var slot = mix(oldHashes[old]) and mask
            while (lengths[slot] != 0) slot = (slot + 1) and mask
            offsets[slot] = oldOffsets[old]
            lengths[slot] = oldLengths[old]
            hashes[slot] = oldHashes[old]
            counts[slot] = oldCounts[old]
        }
    }

    /** Returns the top [n] words by count descending, then word ascending (byte order). */
    fun top(n: Int): List<WordCount> {
        // Word bytes are ASCII, so String comparison matches byte order.
        val order = compareByDescending<Slot> { it.count }.then { a, b -> compareBytes(a, b) }
        val best = ArrayList<Slot>(n + 1)
        for (slot in lengths.indices) {
            if (lengths[slot] == 0) continue
            val candidate = Slot(offsets[slot], lengths[slot], counts[slot])
            if (best.size == n && order.compare(candidate, best[n - 1]) >= 0) continue
            var i = best.size
            while (i > 0 && order.compare(candidate, best[i - 1]) < 0) i--
            best.add(i, candidate)
            if (best.size > n) best.removeAt(n)
        }
        return best.map { WordCount(String(text, it.offset, it.length, Charsets.ISO_8859_1), it.count) }
    }

    private fun compareBytes(a: Slot, b: Slot): Int =
        java.util.Arrays.compare(text, a.offset, a.offset + a.length, text, b.offset, b.offset + b.length)

    private class Slot(val offset: Int, val length: Int, val count: Int)

    private companion object {
        /** Spreads hash bits so that linear probing behaves well with a power-of-two table. */
        fun mix(hash: Int): Int {
            val h = hash * -0x61c88647
            return h xor (h ushr 16)
        }
    }
}

fun main() {
    val input = System.`in`.readAllBytes()
    val top = WordCounter(input).count().top(TOP_N)
    if (top.isEmpty()) return
    val output = buildString {
        for ((word, count) in top) append(count).append(' ').append(word).append('\n')
    }
    BufferedOutputStream(System.out).use { it.write(output.toByteArray(Charsets.ISO_8859_1)) }
}
