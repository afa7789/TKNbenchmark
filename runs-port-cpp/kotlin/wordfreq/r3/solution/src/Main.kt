// wordfreq: print the 10 most frequent ASCII-letter words read from stdin.
package wordfreq

import java.io.BufferedOutputStream

private const val TOP_N = 10

private fun isUpper(b: Int) = b in 'A'.code..'Z'.code
private fun isLower(b: Int) = b in 'a'.code..'z'.code

/** A distinct word, stored as a byte range of the (lowercased) input buffer. */
private class Entry(val start: Int, val length: Int, val hash: Int) {
    var count: Long = 0
}

/**
 * Open-addressing hash table counting words that are byte ranges of [text].
 * Avoids allocating a String per occurrence, which matters for 50 MB inputs.
 */
private class WordCounter(private val text: ByteArray) {
    private var slots = arrayOfNulls<Entry>(1 shl 12)
    private var size = 0

    val entries: List<Entry> get() = slots.filterNotNull()

    fun add(start: Int, length: Int) {
        val hash = hashOf(start, length)
        var mask = slots.size - 1
        var i = hash and mask
        while (true) {
            val e = slots[i] ?: break
            if (e.hash == hash && sameBytes(e, start, length)) {
                e.count++
                return
            }
            i = (i + 1) and mask
        }
        if ((size + 1) * 2 > slots.size) {
            grow()
            mask = slots.size - 1
            i = hash and mask
            while (slots[i] != null) i = (i + 1) and mask
        }
        slots[i] = Entry(start, length, hash).also { it.count = 1 }
        size++
    }

    fun word(e: Entry) = String(text, e.start, e.length, Charsets.ISO_8859_1)

    private fun hashOf(start: Int, length: Int): Int {
        var h = 0
        for (k in start until start + length) h = 31 * h + text[k]
        return h xor (h ushr 16)
    }

    private fun sameBytes(e: Entry, start: Int, length: Int): Boolean =
        e.length == length && text.compareRange(e.start, start, length) == 0

    private fun grow() {
        val bigger = arrayOfNulls<Entry>(slots.size * 2)
        val mask = bigger.size - 1
        for (e in slots) {
            if (e == null) continue
            var i = e.hash and mask
            while (bigger[i] != null) i = (i + 1) and mask
            bigger[i] = e
        }
        slots = bigger
    }

    /** Byte-order comparison of two ranges of the buffer, unsigned per byte. */
    fun compareWords(a: Entry, b: Entry): Int =
        java.util.Arrays.compareUnsigned(text, a.start, a.start + a.length, text, b.start, b.start + b.length)

    private fun ByteArray.compareRange(a: Int, b: Int, length: Int): Int =
        java.util.Arrays.compare(this, a, a + length, this, b, b + length)
}

/** Lowercases [text] in place and counts each maximal run of ASCII letters. */
private fun countWords(text: ByteArray): WordCounter {
    val counter = WordCounter(text)
    val size = text.size
    var i = 0
    while (i < size) {
        while (i < size && !isLetter(text[i].toInt())) i++
        val start = i
        while (i < size) {
            val c = text[i].toInt()
            if (isUpper(c)) {
                text[i] = (c - 'A'.code + 'a'.code).toByte()
            } else if (!isLower(c)) {
                break
            }
            i++
        }
        if (i > start) counter.add(start, i - start)
    }
    return counter
}

private fun isLetter(b: Int) = isLower(b) || isUpper(b)

fun main() {
    val text = System.`in`.readBytes()
    val counter = countWords(text)

    val byRank = compareByDescending<Entry> { it.count }.then(counter::compareWords)
    val top = counter.entries.sortedWith(byRank).take(TOP_N)

    val out = buildString {
        for (e in top) append(e.count).append(' ').append(counter.word(e)).append('\n')
    }
    BufferedOutputStream(System.out).use { it.write(out.toByteArray(Charsets.ISO_8859_1)) }
}
