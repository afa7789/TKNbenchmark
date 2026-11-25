import java.io.BufferedOutputStream
import java.io.PrintStream

private const val TOP_N = 10

/**
 * Open-addressing hash table counting words that live in a shared byte buffer.
 * Each word is identified by its (start, length) slice of [buf], which must already be lowercase.
 */
private class WordCounter(private val buf: ByteArray) {
    private var capacity = 1 shl 12
    private var starts = IntArray(capacity)
    private var lengths = IntArray(capacity) // 0 marks an empty slot; words are never empty
    private var hashes = IntArray(capacity)
    private var counts = IntArray(capacity)
    var size = 0
        private set

    fun add(start: Int, length: Int, hash: Int) {
        val mask = capacity - 1
        var slot = mix(hash) and mask
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
            if (len == length && hashes[slot] == hash && sliceEquals(starts[slot], start, length)) {
                counts[slot]++
                return
            }
            slot = (slot + 1) and mask
        }
    }

    /** Visits every distinct word as (start, length, count). */
    inline fun forEach(action: (start: Int, length: Int, count: Int) -> Unit) {
        for (i in 0..<capacity) {
            if (lengths[i] != 0) action(starts[i], lengths[i], counts[i])
        }
    }

    private fun sliceEquals(a: Int, b: Int, length: Int): Boolean =
        java.util.Arrays.equals(buf, a, a + length, buf, b, b + length)

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
            var slot = mix(oldHashes[i]) and mask
            while (lengths[slot] != 0) slot = (slot + 1) and mask
            starts[slot] = oldStarts[i]
            lengths[slot] = oldLengths[i]
            hashes[slot] = oldHashes[i]
            counts[slot] = oldCounts[i]
        }
    }

    private fun mix(h: Int): Int {
        val x = h * -0x61c88647
        return x xor (x ushr 16)
    }
}

private data class Entry(val word: String, val count: Int)

private val entryOrder = compareByDescending<Entry> { it.count }.thenBy { it.word }

/** Lowercases ASCII letters in place and counts every maximal run of letters. */
private fun countWords(buf: ByteArray, end: Int): WordCounter {
    val counter = WordCounter(buf)
    var i = 0
    while (i < end) {
        val start = i
        var hash = 0
        while (i < end) {
            val c = buf[i].toInt()
            val lower = c or 0x20
            if (lower < 'a'.code || lower > 'z'.code) break
            buf[i] = lower.toByte()
            hash = 31 * hash + lower
            i++
        }
        if (i > start) counter.add(start, i - start, hash) else i++
    }
    return counter
}

/** Returns the [n] most frequent words, ordered by count descending, then word ascending. */
private fun topWords(counter: WordCounter, buf: ByteArray, n: Int): List<Entry> {
    // Bounded selection: keep only the current best n, so huge vocabularies are never sorted.
    val best = ArrayList<Entry>(n + 1)
    var minCount = 0
    counter.forEach { start, length, count ->
        if (best.size == n && count < minCount) return@forEach
        val entry = Entry(String(buf, start, length, Charsets.ISO_8859_1), count)
        var pos = best.size
        while (pos > 0 && entryOrder.compare(entry, best[pos - 1]) < 0) pos--
        if (pos < n) {
            best.add(pos, entry)
            if (best.size > n) best.removeLast()
            minCount = best.last().count
        }
    }
    return best
}

fun main() {
    val buf = System.`in`.readBytes()
    val counter = countWords(buf, buf.size)
    val out = PrintStream(BufferedOutputStream(System.out), false, Charsets.US_ASCII)
    for ((word, count) in topWords(counter, buf, TOP_N)) {
        out.print(count)
        out.print(' ')
        out.print(word)
        out.print('\n')
    }
    out.flush()
}
