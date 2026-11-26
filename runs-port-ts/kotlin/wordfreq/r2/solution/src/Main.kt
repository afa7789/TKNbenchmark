import java.io.BufferedOutputStream

private const val TOP_N = 10

/** A distinct word and how many times it occurred. */
data class WordCount(val word: String, val count: Int)

/** Order by count descending, then word ascending (byte order; words are lowercase ASCII). */
val byFrequency: Comparator<WordCount> =
    compareByDescending<WordCount> { it.count }.thenBy { it.word }

private fun isUpper(b: Int) = b in 0x41..0x5a
private fun isLower(b: Int) = b in 0x61..0x7a

/**
 * Open-addressing hash table counting words that are slices of a shared byte buffer.
 * Avoids allocating a String per occurrence; only distinct words are materialized.
 */
private class WordTable(private val data: ByteArray) {
    private var capacity = 1 shl 14
    private var starts = IntArray(capacity)
    private var lengths = IntArray(capacity) // 0 marks an empty slot
    private var hashes = IntArray(capacity)
    private var counts = IntArray(capacity)
    var size = 0
        private set

    fun increment(start: Int, end: Int, hash: Int) {
        val len = end - start
        val mask = capacity - 1
        var slot = hash and mask
        while (true) {
            val slotLen = lengths[slot]
            if (slotLen == 0) {
                starts[slot] = start
                lengths[slot] = len
                hashes[slot] = hash
                counts[slot] = 1
                if (++size * 2 > capacity) grow()
                return
            }
            if (hashes[slot] == hash && slotLen == len && sameBytes(starts[slot], start, len)) {
                counts[slot]++
                return
            }
            slot = (slot + 1) and mask
        }
    }

    private fun sameBytes(a: Int, b: Int, len: Int): Boolean =
        java.util.Arrays.equals(data, a, a + len, data, b, b + len)

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

    fun entries(): Sequence<WordCount> = lengths.indices.asSequence()
        .filter { lengths[it] != 0 }
        .map { WordCount(String(data, starts[it], lengths[it], Charsets.ISO_8859_1), counts[it]) }
}

private fun mix(h: Int): Int {
    val x = h * -0x61c88647 // golden-ratio multiplier spreads bits for power-of-two tables
    return x xor (x ushr 16)
}

/**
 * Count case-folded words (maximal runs of ASCII letters) in [data].
 * The buffer is lowercased in place.
 */
fun countWords(data: ByteArray): List<WordCount> {
    val table = WordTable(data)
    val len = data.size
    var i = 0
    while (i < len) {
        while (i < len && !isUpper(data[i].toInt()) && !isLower(data[i].toInt())) i++
        if (i >= len) break
        val start = i
        var hash = 0
        while (i < len) {
            var b = data[i].toInt()
            if (isUpper(b)) {
                b = b or 0x20
                data[i] = b.toByte()
            } else if (!isLower(b)) {
                break
            }
            hash = hash * 31 + b
            i++
        }
        table.increment(start, i, mix(hash))
    }
    return table.entries().toList()
}

/** Select the [n] best entries without sorting all of them. */
fun topWords(counts: List<WordCount>, n: Int): List<WordCount> {
    val top = ArrayList<WordCount>(n + 1)
    for (entry in counts) {
        if (top.size == n && byFrequency.compare(entry, top.last()) >= 0) continue
        var pos = top.binarySearch(entry, byFrequency)
        if (pos < 0) pos = -pos - 1
        top.add(pos, entry)
        if (top.size > n) top.removeAt(top.lastIndex)
    }
    return top
}

fun main() {
    val input = System.`in`.readBytes()
    val top = topWords(countWords(input), TOP_N)
    if (top.isEmpty()) return
    val out = buildString {
        for ((word, count) in top) append(count).append(' ').append(word).append('\n')
    }
    BufferedOutputStream(System.out).use { it.write(out.toByteArray(Charsets.ISO_8859_1)) }
}
