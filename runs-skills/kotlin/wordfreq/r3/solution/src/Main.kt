import java.io.BufferedOutputStream
import java.io.PrintStream

/** Number of most frequent words to report. */
private const val TOP_N = 10

/**
 * Counts occurrences of lowercase ASCII words without allocating a String per occurrence.
 * Open addressing with linear probing; word bytes live in a shared growable pool.
 */
private class WordCounter {
    private var capacity = 1 shl 16
    private var mask = capacity - 1
    private var slots = IntArray(capacity) { -1 } // entry index or -1
    private var hashes = IntArray(capacity)

    // Per-entry storage.
    private var offsets = IntArray(1024)
    private var lengths = IntArray(1024)
    private var counts = IntArray(1024)
    var size = 0
        private set

    private var pool = ByteArray(1 shl 16)
    private var poolSize = 0

    fun add(word: ByteArray, len: Int, hash: Int) {
        var slot = hash and mask
        while (true) {
            val entry = slots[slot]
            if (entry < 0) break
            if (hashes[slot] == hash && matches(entry, word, len)) {
                counts[entry]++
                return
            }
            slot = (slot + 1) and mask
        }
        insert(slot, word, len, hash)
    }

    private fun matches(entry: Int, word: ByteArray, len: Int): Boolean {
        if (lengths[entry] != len) return false
        val off = offsets[entry]
        for (i in 0..<len) if (pool[off + i] != word[i]) return false
        return true
    }

    private fun insert(slot: Int, word: ByteArray, len: Int, hash: Int) {
        if (size == offsets.size) {
            val n = size * 2
            offsets = offsets.copyOf(n)
            lengths = lengths.copyOf(n)
            counts = counts.copyOf(n)
        }
        if (poolSize + len > pool.size) pool = pool.copyOf(maxOf(pool.size * 2, poolSize + len))
        System.arraycopy(word, 0, pool, poolSize, len)
        offsets[size] = poolSize
        lengths[size] = len
        counts[size] = 1
        poolSize += len
        slots[slot] = size
        hashes[slot] = hash
        size++
        if (size * 2 > capacity) rehash()
    }

    private fun rehash() {
        val oldSlots = slots
        val oldHashes = hashes
        capacity *= 2
        mask = capacity - 1
        slots = IntArray(capacity) { -1 }
        hashes = IntArray(capacity)
        for (i in oldSlots.indices) {
            val entry = oldSlots[i]
            if (entry < 0) continue
            var slot = oldHashes[i] and mask
            while (slots[slot] >= 0) slot = (slot + 1) and mask
            slots[slot] = entry
            hashes[slot] = oldHashes[i]
        }
    }

    fun count(entry: Int): Int = counts[entry]

    fun word(entry: Int): String = String(pool, offsets[entry], lengths[entry], Charsets.US_ASCII)
}

private fun countWords(input: ByteArray): WordCounter {
    val counter = WordCounter()
    val word = ByteArray(maxOf(1, input.size))
    var len = 0
    var hash = 0
    for (b in input) {
        val c = b.toInt()
        val lower = c or 0x20
        if (lower in 'a'.code..'z'.code) {
            word[len++] = lower.toByte()
            hash = hash * 31 + lower
        } else if (len > 0) {
            counter.add(word, len, mix(hash))
            len = 0
            hash = 0
        }
    }
    if (len > 0) counter.add(word, len, mix(hash))
    return counter
}

/** Spreads polynomial hash bits so low bits are usable as a table index. */
private fun mix(h: Int): Int {
    var x = h * -0x61c88647
    x = x xor (x ushr 16)
    return x
}

/** Returns the top [n] entries ordered by count descending, then word ascending. */
private fun topWords(counter: WordCounter, n: Int): List<Pair<String, Int>> {
    val byRank = compareByDescending<Pair<String, Int>> { it.second }.thenBy { it.first }
    // Bounded selection: keep only the best n candidates seen so far.
    val best = java.util.PriorityQueue(n + 1, byRank.reversed())
    for (entry in 0..<counter.size) {
        val count = counter.count(entry)
        if (best.size == n) {
            val worst = best.peek()
            if (count < worst.second) continue
            val candidate = counter.word(entry) to count
            if (byRank.compare(candidate, worst) >= 0) continue
            best.poll()
            best.add(candidate)
        } else {
            best.add(counter.word(entry) to count)
        }
    }
    return best.sortedWith(byRank)
}

fun main() {
    val input = System.`in`.readBytes()
    val top = topWords(countWords(input), TOP_N)
    PrintStream(BufferedOutputStream(System.out), false, Charsets.US_ASCII).use { out ->
        for ((word, count) in top) out.print("$count $word\n")
    }
}
