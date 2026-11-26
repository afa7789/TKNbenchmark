package wordfreq

import java.util.PriorityQueue

/** A word together with its occurrence count. */
data class WordCount(val word: String, val count: Long)

/**
 * Counts occurrences of byte-string words using an open-addressing hash table.
 * Word bytes are stored contiguously in an arena to avoid per-word allocations.
 */
class WordCounter {
    private var arena = ByteArray(1 shl 16)
    private var arenaSize = 0

    // Per-slot data; a slot is empty when offsets[slot] < 0.
    private var offsets = IntArray(0)
    private var lengths = IntArray(0)
    private var hashes = IntArray(0)
    private var counts = LongArray(0)
    private var mask = 0
    private var size = 0

    init {
        allocate(INITIAL_CAPACITY)
    }

    private fun allocate(capacity: Int) {
        offsets = IntArray(capacity) { -1 }
        lengths = IntArray(capacity)
        hashes = IntArray(capacity)
        counts = LongArray(capacity)
        mask = capacity - 1
    }

    /** Records one occurrence of the word stored in `buf[0, len)` whose precomputed hash is [hash]. */
    fun add(buf: ByteArray, len: Int, hash: Int) {
        var slot = mix(hash) and mask
        while (true) {
            val off = offsets[slot]
            if (off < 0) {
                insert(slot, buf, len, hash)
                return
            }
            if (hashes[slot] == hash && lengths[slot] == len &&
                arena.equalsRange(off, buf, 0, len)
            ) {
                counts[slot]++
                return
            }
            slot = (slot + 1) and mask
        }
    }

    private fun insert(slot: Int, buf: ByteArray, len: Int, hash: Int) {
        if (arenaSize + len > arena.size) {
            val needed = arenaSize.toLong() + len
            val grown = maxOf(needed, arena.size * 2L).coerceAtMost(MAX_ARRAY_SIZE.toLong())
            arena = arena.copyOf(grown.toInt())
        }
        buf.copyInto(arena, destinationOffset = arenaSize, startIndex = 0, endIndex = len)
        offsets[slot] = arenaSize
        lengths[slot] = len
        hashes[slot] = hash
        counts[slot] = 1
        arenaSize += len
        if (++size * 2 > offsets.size) rehash()
    }

    private fun rehash() {
        val oldOffsets = offsets
        val oldLengths = lengths
        val oldHashes = hashes
        val oldCounts = counts
        allocate(oldOffsets.size * 2)
        for (i in oldOffsets.indices) {
            if (oldOffsets[i] < 0) continue
            var slot = mix(oldHashes[i]) and mask
            while (offsets[slot] >= 0) slot = (slot + 1) and mask
            offsets[slot] = oldOffsets[i]
            lengths[slot] = oldLengths[i]
            hashes[slot] = oldHashes[i]
            counts[slot] = oldCounts[i]
        }
    }

    /** Returns the [limit] most frequent words, by count descending then word ascending (byte order). */
    fun top(limit: Int): List<WordCount> {
        if (limit <= 0) return emptyList()
        val order = Comparator<Int>(::compareSlots)
        // The head of the heap is the worst entry currently kept.
        val heap = PriorityQueue(limit + 1, order.reversed())
        for (slot in offsets.indices) {
            if (offsets[slot] < 0) continue
            if (heap.size < limit) {
                heap.add(slot)
            } else if (compareSlots(slot, heap.peek()) < 0) {
                heap.poll()
                heap.add(slot)
            }
        }
        return heap.sortedWith(order).map { slot ->
            WordCount(String(arena, offsets[slot], lengths[slot], Charsets.US_ASCII), counts[slot])
        }
    }

    /** Orders slots so that "better" (more frequent, then lexicographically smaller) comes first. */
    private fun compareSlots(a: Int, b: Int): Int {
        val byCount = counts[b].compareTo(counts[a])
        if (byCount != 0) return byCount
        return java.util.Arrays.compareUnsigned(
            arena, offsets[a], offsets[a] + lengths[a],
            arena, offsets[b], offsets[b] + lengths[b],
        )
    }

    private fun ByteArray.equalsRange(offset: Int, other: ByteArray, otherOffset: Int, len: Int): Boolean =
        java.util.Arrays.equals(this, offset, offset + len, other, otherOffset, otherOffset + len)

    private companion object {
        const val INITIAL_CAPACITY = 1 shl 12
        const val MAX_ARRAY_SIZE = Int.MAX_VALUE - 8

        fun mix(hash: Int): Int {
            val h = hash * 0x9E3779B9.toInt()
            return h xor (h ushr 16)
        }
    }
}
