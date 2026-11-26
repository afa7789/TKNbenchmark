/*
 * wordfreq: read stdin, print the 10 most frequent ASCII-letter words.
 *
 * A word is a maximal run of [A-Za-z], folded to lowercase. Output is
 * "<count> <word>" ordered by count descending, then word ascending (byte order).
 */
package wordfreq

import java.io.IOException
import java.io.InputStream
import java.io.PrintStream
import java.util.Arrays
import kotlin.system.exitProcess

private const val TOP_N = 10
private const val READ_CHUNK = 1 shl 16

/** Growable byte buffer. */
private class ByteBuf(initialCapacity: Int = 64) {
    var data = ByteArray(initialCapacity)
        private set
    var size = 0
        private set

    fun append(b: Byte) {
        if (size == data.size) grow(size + 1)
        data[size++] = b
    }

    fun append(src: ByteArray, offset: Int, length: Int) {
        if (data.size - size < length) grow(size + length)
        System.arraycopy(src, offset, data, size, length)
        size += length
    }

    fun clear() {
        size = 0
    }

    private fun grow(needed: Int) {
        var cap = data.size.coerceAtLeast(64)
        while (cap < needed) {
            check(cap <= Int.MAX_VALUE / 2) { "buffer too large" }
            cap *= 2
        }
        data = data.copyOf(cap)
    }
}

/** A counted word, as reported to the caller. */
data class WordCount(val word: String, val count: Long)

/**
 * Open-addressing hash table from byte-string words to counts.
 * Distinct words are stored back to back in a single arena to avoid per-word allocations.
 */
class WordCounter {
    private var capacity = 1 shl 12 // always a power of two
    private var hashes = IntArray(capacity)
    private var offsets = IntArray(capacity)
    private var lengths = IntArray(capacity)
    private var counts = LongArray(capacity) // 0 marks an empty slot
    private var used = 0
    private val arena = ByteBuf(1 shl 16)

    val distinctWords: Int get() = used

    /** Counts one occurrence of the word `src[offset, offset + length)`. */
    fun add(src: ByteArray, offset: Int, length: Int) {
        val h = hash(src, offset, length)
        var mask = capacity - 1
        var i = h and mask
        while (counts[i] != 0L) {
            if (hashes[i] == h && lengths[i] == length && arenaEquals(offsets[i], src, offset, length)) {
                counts[i]++
                return
            }
            i = (i + 1) and mask
        }

        // New word: keep the load factor at or below 1/2.
        if ((used + 1) * 2 > capacity) {
            grow()
            mask = capacity - 1
            i = h and mask
            while (counts[i] != 0L) i = (i + 1) and mask
        }
        hashes[i] = h
        offsets[i] = arena.size
        lengths[i] = length
        counts[i] = 1
        arena.append(src, offset, length)
        used++
    }

    /** Returns the [n] highest-ranked words: count descending, then word ascending. */
    fun top(n: Int): List<WordCount> {
        val top = IntArray(n)
        var size = 0
        for (slot in 0 until capacity) {
            if (counts[slot] == 0L) continue
            if (size == n && !ranksBefore(slot, top[n - 1])) continue
            var j = if (size < n) size++ else n - 1
            while (j > 0 && ranksBefore(slot, top[j - 1])) {
                top[j] = top[j - 1]
                j--
            }
            top[j] = slot
        }
        return (0 until size).map { k ->
            val slot = top[k]
            WordCount(String(arena.data, offsets[slot], lengths[slot], Charsets.ISO_8859_1), counts[slot])
        }
    }

    private fun ranksBefore(a: Int, b: Int): Boolean =
        if (counts[a] != counts[b]) counts[a] > counts[b] else compareWords(a, b) < 0

    private fun compareWords(a: Int, b: Int): Int {
        val data = arena.data
        return Arrays.compareUnsigned(
            data, offsets[a], offsets[a] + lengths[a],
            data, offsets[b], offsets[b] + lengths[b],
        )
    }

    private fun arenaEquals(arenaOffset: Int, src: ByteArray, offset: Int, length: Int): Boolean =
        Arrays.equals(arena.data, arenaOffset, arenaOffset + length, src, offset, offset + length)

    private fun grow() {
        check(capacity <= Int.MAX_VALUE / 2) { "too many distinct words" }
        val newCapacity = capacity * 2
        val mask = newCapacity - 1
        val newHashes = IntArray(newCapacity)
        val newOffsets = IntArray(newCapacity)
        val newLengths = IntArray(newCapacity)
        val newCounts = LongArray(newCapacity)
        for (slot in 0 until capacity) {
            if (counts[slot] == 0L) continue
            var j = hashes[slot] and mask
            while (newCounts[j] != 0L) j = (j + 1) and mask
            newHashes[j] = hashes[slot]
            newOffsets[j] = offsets[slot]
            newLengths[j] = lengths[slot]
            newCounts[j] = counts[slot]
        }
        capacity = newCapacity
        hashes = newHashes
        offsets = newOffsets
        lengths = newLengths
        counts = newCounts
    }

    private companion object {
        /** FNV-1a (32-bit) with a final avalanche so the low bits are well mixed. */
        fun hash(src: ByteArray, offset: Int, length: Int): Int {
            var h = 0x811c9dc5.toInt()
            for (k in offset until offset + length) {
                h = (h xor (src[k].toInt() and 0xff)) * 0x01000193
            }
            h = h xor (h ushr 16)
            h *= 0x85ebca6b.toInt()
            h = h xor (h ushr 13)
            return h
        }
    }
}

private fun isAsciiLetter(b: Int): Boolean = ((b or 0x20) - 'a'.code).toUInt() < 26u

/** Reads [input] to the end, counting every word in it. */
fun countWords(input: InputStream): WordCounter {
    val counter = WordCounter()
    val chunk = ByteArray(READ_CHUNK)
    val pending = ByteBuf() // a word that spans read chunks

    while (true) {
        val got = input.read(chunk)
        if (got < 0) break
        var i = 0
        while (i < got) {
            if (!isAsciiLetter(chunk[i].toInt())) {
                if (pending.size > 0) {
                    counter.add(pending.data, 0, pending.size)
                    pending.clear()
                }
                i++
                continue
            }
            val start = i
            while (i < got && isAsciiLetter(chunk[i].toInt())) {
                chunk[i] = (chunk[i].toInt() or 0x20).toByte() // fold to lowercase
                i++
            }
            if (i < got && pending.size == 0) {
                // The word lies entirely inside this chunk: count it in place.
                counter.add(chunk, start, i - start)
            } else {
                pending.append(chunk, start, i - start)
            }
        }
    }
    if (pending.size > 0) counter.add(pending.data, 0, pending.size)
    return counter
}

fun main() {
    val top = try {
        countWords(System.`in`).top(TOP_N)
    } catch (e: IOException) {
        System.err.println("wordfreq: read error: ${e.message}")
        exitProcess(1)
    }

    val out = PrintStream(System.out.buffered(), false, Charsets.ISO_8859_1)
    val text = buildString {
        for ((word, count) in top) append(count).append(' ').append(word).append('\n')
    }
    out.print(text)
    out.flush()
    if (out.checkError()) exitProcess(1)
}
