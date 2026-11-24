import java.io.InputStream
import java.io.PrintStream

private const val TOP_N = 10

/**
 * Open-addressing hash table counting lowercase ASCII words.
 * Word bytes are stored contiguously in a growable arena to avoid per-word allocations.
 */
class WordCounter {
    private var arena = ByteArray(1 shl 16)
    private var arenaSize = 0

    // Per-slot data; a slot is empty when counts[slot] == 0.
    private var capacity = 1 shl 12
    private var offsets = IntArray(capacity)
    private var lengths = IntArray(capacity)
    private var hashes = IntArray(capacity)
    private var counts = IntArray(capacity)
    private var size = 0

    /** Adds one occurrence of the word stored in [buf] at [start] until [end] (already lowercased). */
    fun add(buf: ByteArray, start: Int, end: Int, hash: Int) {
        val len = end - start
        val mask = capacity - 1
        var slot = hash and mask
        while (counts[slot] != 0) {
            if (hashes[slot] == hash && lengths[slot] == len &&
                arena.regionEquals(offsets[slot], buf, start, len)
            ) {
                counts[slot]++
                return
            }
            slot = (slot + 1) and mask
        }
        offsets[slot] = store(buf, start, len)
        lengths[slot] = len
        hashes[slot] = hash
        counts[slot] = 1
        if (++size * 2 > capacity) grow()
    }

    /** Returns the [n] most frequent words, by count descending then word ascending. */
    fun top(n: Int): List<Pair<String, Int>> =
        (0 until capacity)
            .filter { counts[it] != 0 }
            .map { String(arena, offsets[it], lengths[it], Charsets.US_ASCII) to counts[it] }
            .sortedWith(compareByDescending<Pair<String, Int>> { it.second }.thenBy { it.first })
            .take(n)

    private fun store(buf: ByteArray, start: Int, len: Int): Int {
        if (arenaSize + len > arena.size) {
            arena = arena.copyOf(maxOf(arena.size * 2, arenaSize + len))
        }
        System.arraycopy(buf, start, arena, arenaSize, len)
        return arenaSize.also { arenaSize += len }
    }

    private fun grow() {
        val oldOffsets = offsets
        val oldLengths = lengths
        val oldHashes = hashes
        val oldCounts = counts
        capacity *= 2
        offsets = IntArray(capacity)
        lengths = IntArray(capacity)
        hashes = IntArray(capacity)
        counts = IntArray(capacity)
        val mask = capacity - 1
        for (i in oldCounts.indices) {
            if (oldCounts[i] == 0) continue
            var slot = oldHashes[i] and mask
            while (counts[slot] != 0) slot = (slot + 1) and mask
            offsets[slot] = oldOffsets[i]
            lengths[slot] = oldLengths[i]
            hashes[slot] = oldHashes[i]
            counts[slot] = oldCounts[i]
        }
    }

    private fun ByteArray.regionEquals(offset: Int, other: ByteArray, otherOffset: Int, len: Int): Boolean {
        for (i in 0 until len) {
            if (this[offset + i] != other[otherOffset + i]) return false
        }
        return true
    }
}

private fun mix(h: Int): Int {
    var x = h * -0x61c88647
    x = x xor (x ushr 16)
    return x
}

/** Streams [input], splitting it into ASCII-letter words and counting them case-insensitively. */
fun countWords(input: InputStream): WordCounter {
    val counter = WordCounter()
    // Holds the current (possibly partial) word at the front, followed by fresh input.
    var buf = ByteArray(1 shl 16)
    var wordLen = 0
    var hash = 0

    while (true) {
        if (wordLen == buf.size) buf = buf.copyOf(buf.size * 2)
        val read = input.read(buf, wordLen, buf.size - wordLen)
        if (read < 0) break
        val end = wordLen + read
        var wordStart = 0
        var i = wordLen
        while (i < end) {
            val b = buf[i].toInt()
            val lower = b or 0x20
            if (lower in 'a'.code..'z'.code) {
                buf[i] = lower.toByte()
                hash = hash * 31 + lower
            } else {
                if (i > wordStart) counter.add(buf, wordStart, i, mix(hash))
                hash = 0
                wordStart = i + 1
            }
            i++
        }
        // Carry an unfinished word over to the next read.
        wordLen = end - wordStart
        System.arraycopy(buf, wordStart, buf, 0, wordLen)
    }
    if (wordLen > 0) counter.add(buf, 0, wordLen, mix(hash))
    return counter
}

fun main() {
    val counter = countWords(System.`in`)
    val out = PrintStream(System.out.buffered(), false, Charsets.US_ASCII)
    for ((word, count) in counter.top(TOP_N)) {
        out.print(count)
        out.print(' ')
        out.print(word)
        out.print('\n')
    }
    out.flush()
}
