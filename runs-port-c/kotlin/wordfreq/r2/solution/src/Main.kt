/*
 * wordfreq: read stdin, print the 10 most frequent ASCII words.
 *
 * A word is a maximal run of ASCII letters, folded to lowercase. Output is
 * "<count> <word>" per line, ordered by count descending, then word ascending
 * (byte order), at most TOP_N lines.
 */
package wordfreq

import java.io.BufferedOutputStream

private const val TOP_N = 10

private fun isAsciiLetter(b: Byte): Boolean = ((b.toInt() or 0x20) - 'a'.code).toUInt() < 26u

/**
 * Open-addressing hash table counting words that live in [text] as (offset, length) slices.
 * Words are referenced in place, so counting allocates nothing per word.
 */
private class WordCounter(private val text: ByteArray) {
    private var capacity = 1024 // always a power of two
    private var starts = IntArray(capacity)
    private var lengths = IntArray(capacity) // 0 marks an empty slot
    private var hashes = IntArray(capacity)
    private var counts = LongArray(capacity)
    private var size = 0

    /** Increments the count of the word `text[start until start + length]`, inserting it if absent. */
    fun add(start: Int, length: Int) {
        val hash = hash(start, length)
        var mask = capacity - 1
        var i = hash and mask
        while (lengths[i] != 0) {
            if (hashes[i] == hash && lengths[i] == length && sameBytes(starts[i], start, length)) {
                counts[i]++
                return
            }
            i = (i + 1) and mask
        }
        // Keep the load factor at or below 1/2.
        if ((size + 1) * 2 > capacity) {
            grow()
            mask = capacity - 1
            i = hash and mask
            while (lengths[i] != 0) i = (i + 1) and mask
        }
        starts[i] = start
        lengths[i] = length
        hashes[i] = hash
        counts[i] = 1
        size++
    }

    /** Returns the [limit] best-ranked words, best first. */
    fun top(limit: Int): List<WordCount> {
        val best = ArrayList<WordCount>(limit + 1)
        for (slot in 0 until capacity) {
            if (lengths[slot] == 0) continue
            val count = counts[slot]
            if (best.size == limit && !ranksBefore(slot, best.last())) continue
            val entry = WordCount(count, starts[slot], lengths[slot])
            var pos = best.size
            while (pos > 0 && ranksBefore(slot, best[pos - 1])) pos--
            best.add(pos, entry)
            if (best.size > limit) best.removeAt(best.lastIndex)
        }
        return best
    }

    private fun ranksBefore(slot: Int, other: WordCount): Boolean {
        if (counts[slot] != other.count) return counts[slot] > other.count
        return compareSlices(starts[slot], lengths[slot], other.start, other.length) < 0
    }

    private fun compareSlices(aStart: Int, aLen: Int, bStart: Int, bLen: Int): Int {
        val n = minOf(aLen, bLen)
        for (k in 0 until n) {
            val diff = (text[aStart + k].toInt() and 0xff) - (text[bStart + k].toInt() and 0xff)
            if (diff != 0) return diff
        }
        return aLen - bLen
    }

    private fun sameBytes(a: Int, b: Int, length: Int): Boolean {
        for (k in 0 until length) if (text[a + k] != text[b + k]) return false
        return true
    }

    /** FNV-1a (32-bit) with a final avalanche so the low bits are well mixed. */
    private fun hash(start: Int, length: Int): Int {
        var h = 0x811c9dc5.toInt()
        for (k in start until start + length) {
            h = (h xor text[k].toInt()) * 0x01000193
        }
        return h xor (h ushr 16)
    }

    private fun grow() {
        val newCapacity = capacity * 2
        val newStarts = IntArray(newCapacity)
        val newLengths = IntArray(newCapacity)
        val newHashes = IntArray(newCapacity)
        val newCounts = LongArray(newCapacity)
        val mask = newCapacity - 1
        for (slot in 0 until capacity) {
            if (lengths[slot] == 0) continue
            var j = hashes[slot] and mask
            while (newLengths[j] != 0) j = (j + 1) and mask
            newStarts[j] = starts[slot]
            newLengths[j] = lengths[slot]
            newHashes[j] = hashes[slot]
            newCounts[j] = counts[slot]
        }
        capacity = newCapacity
        starts = newStarts
        lengths = newLengths
        hashes = newHashes
        counts = newCounts
    }
}

private class WordCount(val count: Long, val start: Int, val length: Int)

/** Lowercases every word of [text] in place and counts them. */
private fun countWords(text: ByteArray): WordCounter {
    val counter = WordCounter(text)
    var i = 0
    val n = text.size
    while (i < n) {
        while (i < n && !isAsciiLetter(text[i])) i++
        val start = i
        while (i < n && isAsciiLetter(text[i])) {
            text[i] = (text[i].toInt() or 0x20).toByte()
            i++
        }
        if (i > start) counter.add(start, i - start)
    }
    return counter
}

fun main() {
    val text = System.`in`.readBytes()
    val top = countWords(text).top(TOP_N)
    BufferedOutputStream(System.out, 1 shl 12).use { out ->
        for (entry in top) {
            out.write("${entry.count} ".toByteArray(Charsets.US_ASCII))
            out.write(text, entry.start, entry.length)
            out.write('\n'.code)
        }
    }
}
