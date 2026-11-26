/**
 * wordfreq: read all of stdin, print the 10 most frequent ASCII words.
 *
 * Words are counted in an open-addressing hash table that references word
 * spans inside the (lower-cased in place) input buffer, so no per-word
 * strings are allocated while scanning.
 */
package wordfreq

import java.io.BufferedOutputStream

private const val TOP_N = 10
private const val INITIAL_CAPACITY = 1 shl 12

/** Lower-case table: maps ASCII letters to lower case, everything else to 0. */
private val LOWER = ByteArray(256).also { table ->
    for (c in 'A'..'Z') table[c.code] = (c.code or 0x20).toByte()
    for (c in 'a'..'z') table[c.code] = c.code.toByte()
}

/** A distinct word together with its number of occurrences. */
data class WordCount(val word: String, val count: Long)

/** Orders by count descending, then by word ascending (byte order; words are pure ASCII). */
val byCountThenWord: Comparator<WordCount> =
    compareByDescending<WordCount> { it.count }.thenBy { it.word }

/** Counts word spans of [buf] in parallel arrays indexed by slot; a length of 0 marks an empty slot. */
class WordTable(private val buf: ByteArray, capacity: Int = INITIAL_CAPACITY) {
    private var mask = 0
    private var hashes = IntArray(0)
    private var starts = IntArray(0)
    private var lens = IntArray(0)
    private var counts = LongArray(0)
    var size = 0
        private set

    init {
        require(capacity > 0 && capacity and (capacity - 1) == 0) { "capacity must be a power of two" }
        allocate(capacity)
    }

    private fun allocate(capacity: Int) {
        mask = capacity - 1
        hashes = IntArray(capacity)
        starts = IntArray(capacity)
        lens = IntArray(capacity)
        counts = LongArray(capacity)
    }

    /** Count one occurrence of buf[start, start + len), already lower-cased. */
    fun add(start: Int, len: Int, hash: Int) {
        var i = hash and mask
        while (true) {
            val l = lens[i]
            if (l == 0) break
            if (l == len && hashes[i] == hash && spanEquals(starts[i], start, len)) {
                counts[i]++
                return
            }
            i = (i + 1) and mask
        }
        hashes[i] = hash
        starts[i] = start
        lens[i] = len
        counts[i] = 1
        if (++size * 2 > mask + 1) grow()
    }

    private fun spanEquals(a: Int, b: Int, len: Int): Boolean {
        for (k in 0 until len) if (buf[a + k] != buf[b + k]) return false
        return true
    }

    private fun grow() {
        val oldHashes = hashes
        val oldStarts = starts
        val oldLens = lens
        val oldCounts = counts
        allocate((mask + 1) * 2)
        for (j in oldLens.indices) {
            if (oldLens[j] == 0) continue
            var i = oldHashes[j] and mask
            while (lens[i] != 0) i = (i + 1) and mask
            hashes[i] = oldHashes[j]
            starts[i] = oldStarts[j]
            lens[i] = oldLens[j]
            counts[i] = oldCounts[j]
        }
    }

    /** Visits every distinct word span and its count, in slot order. */
    fun forEachSpan(action: (start: Int, len: Int, count: Long) -> Unit) {
        for (i in 0..mask) if (lens[i] != 0) action(starts[i], lens[i], counts[i])
    }

    fun word(start: Int, len: Int): String = String(buf, start, len, Charsets.ISO_8859_1)
}

/** Count words in [buf]. Lower-cases letters in place. */
fun countWords(buf: ByteArray): WordTable {
    val table = WordTable(buf)
    val n = buf.size
    var i = 0
    while (i < n) {
        var c = LOWER[buf[i].toInt() and 0xff]
        if (c.toInt() == 0) {
            i++
            continue
        }
        val start = i
        var hash = 0x811c9dc5.toInt() // FNV-1a
        do {
            buf[i] = c
            hash = (hash xor c.toInt()) * 0x01000193
            i++
            c = if (i < n) LOWER[buf[i].toInt() and 0xff] else 0
        } while (c.toInt() != 0)
        table.add(start, i - start, hash)
    }
    return table
}

/** Selects the [limit] best entries of [table] by [byCountThenWord], in order. */
fun topWords(table: WordTable, limit: Int): List<WordCount> {
    val top = ArrayList<WordCount>(limit + 1)
    table.forEachSpan { start, len, count ->
        // Cheap rejection before materialising a String: strictly lower counts can never enter a full list.
        if (top.size == limit && count < top[limit - 1].count) return@forEachSpan
        val entry = WordCount(table.word(start, len), count)
        if (top.size == limit && byCountThenWord.compare(entry, top[limit - 1]) >= 0) return@forEachSpan
        var pos = top.size
        while (pos > 0 && byCountThenWord.compare(entry, top[pos - 1]) < 0) pos--
        top.add(pos, entry)
        if (top.size > limit) top.removeAt(top.lastIndex)
    }
    return top
}

fun main() {
    val input = System.`in`.readBytes()
    val top = topWords(countWords(input), TOP_N)
    if (top.isEmpty()) return
    val out = buildString { top.forEach { append(it.count).append(' ').append(it.word).append('\n') } }
    BufferedOutputStream(System.out).apply {
        write(out.toByteArray(Charsets.ISO_8859_1))
        flush()
    }
}
