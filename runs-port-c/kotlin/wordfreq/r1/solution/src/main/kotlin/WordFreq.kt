/*
 * wordfreq: read stdin, print the 10 most frequent ASCII-letter words
 * (case-folded), ordered by count descending, then word ascending.
 */
import java.io.BufferedOutputStream
import java.io.InputStream
import java.io.OutputStream

private const val TOP_N = 10
private const val READ_CHUNK = 1 shl 16

/** A counted word, decoded for ranking and output. */
data class WordCount(val word: String, val count: Long)

/** Ranking order: count descending, then word ascending (byte order; words are pure ASCII). */
val RANKING: Comparator<WordCount> = compareByDescending<WordCount> { it.count }.thenBy { it.word }

/**
 * Open-addressing hash table counting byte-string words. Word bytes are kept in a
 * single growable arena so that counting allocates nothing per occurrence.
 */
class WordCounter(initialCapacity: Int = 1 shl 12) {
    init {
        require(initialCapacity > 0 && initialCapacity and (initialCapacity - 1) == 0) {
            "capacity must be a power of two"
        }
    }

    private var capacity = initialCapacity
    private var size = 0

    // Per-slot data; a count of 0 marks an empty slot.
    private var offsets = IntArray(capacity)
    private var lengths = IntArray(capacity)
    private var hashes = IntArray(capacity)
    private var counts = LongArray(capacity)

    private var arena = ByteArray(1 shl 16)
    private var arenaUsed = 0

    /** Records one occurrence of the word `bytes[start until start + length]`. */
    fun add(bytes: ByteArray, start: Int, length: Int) {
        val h = hash(bytes, start, length)
        val mask = capacity - 1
        var i = h and mask
        while (counts[i] != 0L) {
            if (hashes[i] == h && lengths[i] == length &&
                arena.regionEquals(offsets[i], bytes, start, length)
            ) {
                counts[i]++
                return
            }
            i = (i + 1) and mask
        }
        offsets[i] = store(bytes, start, length)
        lengths[i] = length
        hashes[i] = h
        counts[i] = 1
        // Keep load factor at or below 1/2.
        if (++size * 2 > capacity) grow()
    }

    /** Returns the [n] highest-ranked words according to [RANKING]. */
    fun top(n: Int): List<WordCount> {
        val best = ArrayList<WordCount>(n + 1)
        for (i in 0 until capacity) {
            val count = counts[i]
            if (count == 0L) continue
            // Cheap reject by count before decoding the word.
            if (best.size == n && count < best.last().count) continue
            val candidate = WordCount(String(arena, offsets[i], lengths[i], Charsets.ISO_8859_1), count)
            if (best.size == n && RANKING.compare(candidate, best.last()) >= 0) continue
            val pos = best.binarySearch(candidate, RANKING).let { if (it < 0) -it - 1 else it }
            best.add(pos, candidate)
            if (best.size > n) best.removeAt(best.lastIndex)
        }
        return best
    }

    private fun store(bytes: ByteArray, start: Int, length: Int): Int {
        if (arena.size - arenaUsed < length) {
            var newSize = arena.size.toLong() * 2
            while (newSize - arenaUsed < length) newSize *= 2
            arena = arena.copyOf(minOf(newSize, Int.MAX_VALUE.toLong() - 8).toInt())
        }
        val offset = arenaUsed
        bytes.copyInto(arena, offset, start, start + length)
        arenaUsed += length
        return offset
    }

    private fun grow() {
        val newCapacity = capacity * 2
        val mask = newCapacity - 1
        val newOffsets = IntArray(newCapacity)
        val newLengths = IntArray(newCapacity)
        val newHashes = IntArray(newCapacity)
        val newCounts = LongArray(newCapacity)
        for (i in 0 until capacity) {
            if (counts[i] == 0L) continue
            var j = hashes[i] and mask
            while (newCounts[j] != 0L) j = (j + 1) and mask
            newOffsets[j] = offsets[i]
            newLengths[j] = lengths[i]
            newHashes[j] = hashes[i]
            newCounts[j] = counts[i]
        }
        offsets = newOffsets
        lengths = newLengths
        hashes = newHashes
        counts = newCounts
        capacity = newCapacity
    }

    private companion object {
        /** 64-bit FNV-1a, folded to 32 bits. */
        fun hash(bytes: ByteArray, start: Int, length: Int): Int {
            var h = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
            for (k in start until start + length) {
                h = (h xor (bytes[k].toLong() and 0xFF)) * 0x100000001b3L
            }
            return (h xor (h ushr 32)).toInt()
        }

        fun ByteArray.regionEquals(offset: Int, other: ByteArray, start: Int, length: Int): Boolean =
            java.util.Arrays.equals(this, offset, offset + length, other, start, start + length)
    }
}

private fun isAsciiLetter(b: Byte): Boolean = ((b.toInt() or 0x20) - 'a'.code).toUInt() < 26u

/** Splits [input] into case-folded ASCII-letter words and counts them. */
fun countWords(input: InputStream): WordCounter {
    val counter = WordCounter()
    val chunk = ByteArray(READ_CHUNK)
    // Holds a word that spans a chunk boundary.
    var pending = ByteArray(64)
    var pendingLength = 0

    while (true) {
        val read = input.read(chunk)
        if (read < 0) break
        var i = 0
        while (i < read) {
            if (!isAsciiLetter(chunk[i])) {
                if (pendingLength > 0) {
                    counter.add(pending, 0, pendingLength)
                    pendingLength = 0
                }
                i++
                continue
            }
            val start = i
            while (i < read && isAsciiLetter(chunk[i])) {
                chunk[i] = (chunk[i].toInt() or 0x20).toByte()
                i++
            }
            val endsInChunk = i < read
            if (pendingLength == 0 && endsInChunk) {
                counter.add(chunk, start, i - start)
            } else {
                val length = i - start
                if (pendingLength + length > pending.size) {
                    pending = pending.copyOf(maxOf(pending.size * 2, pendingLength + length))
                }
                chunk.copyInto(pending, pendingLength, start, i)
                pendingLength += length
                if (endsInChunk) {
                    counter.add(pending, 0, pendingLength)
                    pendingLength = 0
                }
            }
        }
    }
    if (pendingLength > 0) counter.add(pending, 0, pendingLength)
    return counter
}

fun writeReport(top: List<WordCount>, output: OutputStream) {
    output.bufferedWriter(Charsets.ISO_8859_1).apply {
        for ((word, count) in top) {
            append(count.toString()).append(' ').append(word).append('\n')
        }
        flush()
    }
}

fun main() {
    val counter = countWords(System.`in`)
    writeReport(counter.top(TOP_N), BufferedOutputStream(System.out))
}
