package wordfreq

import java.util.Arrays
import java.util.PriorityQueue

/** A word together with its occurrence count. */
data class WordCount(val word: String, val count: Int)

/**
 * Counts occurrences of byte-string words using an open-addressing hash table.
 * Word bytes are stored contiguously in a single arena to avoid per-word allocation.
 */
internal class WordCounter {
    private var slots = IntArray(INITIAL_SLOTS) { EMPTY }
    private var mask = slots.size - 1

    private var size = 0
    private var hashes = IntArray(INITIAL_ENTRIES)
    private var offsets = IntArray(INITIAL_ENTRIES)
    private var lengths = IntArray(INITIAL_ENTRIES)
    private var counts = IntArray(INITIAL_ENTRIES)

    private var arena = ByteArray(INITIAL_ARENA)
    private var arenaUsed = 0

    /** Records one occurrence of the word stored in `buf[0, len)`. */
    fun add(buf: ByteArray, len: Int) {
        val hash = hash(buf, len)
        var slot = hash and mask
        while (true) {
            val entry = slots[slot]
            if (entry == EMPTY) {
                insert(slot, hash, buf, len)
                return
            }
            if (hashes[entry] == hash && lengths[entry] == len &&
                Arrays.equals(arena, offsets[entry], offsets[entry] + len, buf, 0, len)
            ) {
                counts[entry]++
                return
            }
            slot = (slot + 1) and mask
        }
    }

    /** Returns up to [limit] words ordered by count descending, then word ascending. */
    fun top(limit: Int): List<WordCount> {
        if (limit <= 0) return emptyList()
        val rank = Comparator<Int>(::compareEntries)
        // Max-heap on rank so the worst retained entry is at the head.
        val heap = PriorityQueue(limit + 1, rank.reversed())
        for (i in 0 until size) {
            if (heap.size < limit) {
                heap.add(i)
            } else if (compareEntries(i, heap.peek()) < 0) {
                heap.poll()
                heap.add(i)
            }
        }
        return heap.sortedWith(rank).map { e ->
            WordCount(String(arena, offsets[e], lengths[e], Charsets.US_ASCII), counts[e])
        }
    }

    private fun compareEntries(a: Int, b: Int): Int {
        val byCount = counts[b].compareTo(counts[a])
        if (byCount != 0) return byCount
        return Arrays.compareUnsigned(
            arena, offsets[a], offsets[a] + lengths[a],
            arena, offsets[b], offsets[b] + lengths[b],
        )
    }

    private fun insert(slot: Int, hash: Int, buf: ByteArray, len: Int) {
        if (size == counts.size) {
            val capacity = size * 2
            hashes = hashes.copyOf(capacity)
            offsets = offsets.copyOf(capacity)
            lengths = lengths.copyOf(capacity)
            counts = counts.copyOf(capacity)
        }
        ensureArenaCapacity(len)
        buf.copyInto(arena, destinationOffset = arenaUsed, startIndex = 0, endIndex = len)

        val entry = size++
        hashes[entry] = hash
        offsets[entry] = arenaUsed
        lengths[entry] = len
        counts[entry] = 1
        arenaUsed += len
        slots[slot] = entry

        if (size > slots.size * MAX_LOAD) rehash()
    }

    private fun ensureArenaCapacity(extra: Int) {
        val required = arenaUsed.toLong() + extra
        if (required > arena.size) {
            val grown = maxOf(required, arena.size.toLong() * 2)
            arena = arena.copyOf(minOf(grown, MAX_ARRAY_SIZE.toLong()).toInt())
        }
    }

    private fun rehash() {
        val grown = IntArray(slots.size * 2) { EMPTY }
        val newMask = grown.size - 1
        for (entry in 0 until size) {
            var slot = hashes[entry] and newMask
            while (grown[slot] != EMPTY) slot = (slot + 1) and newMask
            grown[slot] = entry
        }
        slots = grown
        mask = newMask
    }

    private companion object {
        const val EMPTY = -1
        const val MAX_LOAD = 0.5
        const val INITIAL_SLOTS = 1 shl 12
        const val INITIAL_ENTRIES = 1024
        const val INITIAL_ARENA = 1 shl 16
        const val MAX_ARRAY_SIZE = Int.MAX_VALUE - 8

        /** FNV-1a followed by a finalizer so low bits are well mixed for masking. */
        fun hash(buf: ByteArray, len: Int): Int {
            var h = 0x811C9DC5.toInt()
            for (i in 0 until len) {
                h = (h xor buf[i].toInt()) * 0x01000193
            }
            h = h xor (h ushr 16)
            h *= 0x85EBCA6B.toInt()
            h = h xor (h ushr 13)
            return h
        }
    }
}
