package wordfreq

/**
 * Counts occurrences of byte-string words using an open-addressing hash table.
 * Word bytes are stored contiguously in a single arena to avoid per-word allocation.
 */
class WordCounter {

    /** A word together with its occurrence count. */
    data class Entry(val word: String, val count: Int)

    private var arena = ByteArray(1 shl 16)
    private var arenaSize = 0

    // Per-entry columns, indexed by entry id.
    private var offsets = IntArray(INITIAL_CAPACITY)
    private var lengths = IntArray(INITIAL_CAPACITY)
    private var hashes = IntArray(INITIAL_CAPACITY)
    private var counts = IntArray(INITIAL_CAPACITY)

    /** Number of distinct words recorded. */
    var size = 0
        private set

    // Hash slots hold entry id + 1; zero marks an empty slot.
    private var slots = IntArray(INITIAL_CAPACITY * 2)
    private var mask = slots.size - 1

    /** Records one occurrence of `word[0 until length]`. */
    fun add(word: ByteArray, length: Int) {
        val hash = hash(word, length)
        var slot = hash and mask
        while (true) {
            val id = slots[slot] - 1
            if (id < 0) {
                insert(slot, word, length, hash)
                return
            }
            if (hashes[id] == hash && matches(id, word, length)) {
                counts[id]++
                return
            }
            slot = (slot + 1) and mask
        }
    }

    /** Returns the [limit] most frequent words, by count descending then word ascending. */
    fun top(limit: Int): List<Entry> {
        val n = minOf(limit, size)
        if (n <= 0) return emptyList()
        // Bounded insertion: keep the best n ids seen so far in sorted order.
        val best = IntArray(n)
        var filled = 0
        for (id in 0 until size) {
            if (filled == n && compareIds(id, best[n - 1]) >= 0) continue
            var pos = if (filled < n) filled++ else n - 1
            while (pos > 0 && compareIds(id, best[pos - 1]) < 0) {
                best[pos] = best[pos - 1]
                pos--
            }
            best[pos] = id
        }
        return best.map { id -> Entry(String(arena, offsets[id], lengths[id], Charsets.ISO_8859_1), counts[id]) }
    }

    private fun compareIds(a: Int, b: Int): Int {
        val byCount = counts[b].compareTo(counts[a])
        if (byCount != 0) return byCount
        return java.util.Arrays.compareUnsigned(
            arena, offsets[a], offsets[a] + lengths[a],
            arena, offsets[b], offsets[b] + lengths[b],
        )
    }

    private fun matches(id: Int, word: ByteArray, length: Int): Boolean {
        val offset = offsets[id]
        return lengths[id] == length &&
            java.util.Arrays.equals(arena, offset, offset + length, word, 0, length)
    }

    private fun insert(slot: Int, word: ByteArray, length: Int, hash: Int) {
        if (size == offsets.size) growEntries()
        ensureArena(length)
        word.copyInto(arena, destinationOffset = arenaSize, endIndex = length)
        val id = size++
        offsets[id] = arenaSize
        lengths[id] = length
        hashes[id] = hash
        counts[id] = 1
        arenaSize += length
        slots[slot] = id + 1
        if (size * 2 > slots.size) rehash()
    }

    private fun ensureArena(extra: Int) {
        val needed = arenaSize.toLong() + extra
        if (needed > arena.size) {
            val grown = maxOf(needed, arena.size.toLong() * 2)
            arena = arena.copyOf(minOf(grown, (Int.MAX_VALUE - 8).toLong()).toInt())
        }
    }

    private fun growEntries() {
        val capacity = offsets.size * 2
        offsets = offsets.copyOf(capacity)
        lengths = lengths.copyOf(capacity)
        hashes = hashes.copyOf(capacity)
        counts = counts.copyOf(capacity)
    }

    private fun rehash() {
        slots = IntArray(slots.size * 2)
        mask = slots.size - 1
        for (id in 0 until size) {
            var slot = hashes[id] and mask
            while (slots[slot] != 0) slot = (slot + 1) and mask
            slots[slot] = id + 1
        }
    }

    private companion object {
        const val INITIAL_CAPACITY = 1 shl 12

        fun hash(word: ByteArray, length: Int): Int {
            var h = 0x811C9DC5.toInt()
            for (i in 0 until length) h = (h xor word[i].toInt()) * 0x01000193
            return h xor (h ushr 16)
        }
    }
}
