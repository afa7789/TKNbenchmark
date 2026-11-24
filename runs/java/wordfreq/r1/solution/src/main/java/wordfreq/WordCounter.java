package wordfreq;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.PriorityQueue;

/**
 * Counts occurrences of byte-string words using an open-addressing hash table.
 * Word bytes are stored contiguously in an arena to avoid per-word allocations.
 */
final class WordCounter {

    /** A word together with its occurrence count. */
    record Entry(String word, long count) {}

    private static final int INITIAL_CAPACITY = 1 << 12;

    private byte[] arena = new byte[1 << 16];
    private int arenaSize;

    // Per-slot data; slot is empty when offsets[slot] < 0.
    private int[] offsets;
    private int[] lengths;
    private int[] hashes;
    private long[] counts;
    private int size;
    private int mask;

    WordCounter() {
        allocate(INITIAL_CAPACITY);
    }

    private void allocate(int capacity) {
        offsets = new int[capacity];
        Arrays.fill(offsets, -1);
        lengths = new int[capacity];
        hashes = new int[capacity];
        counts = new long[capacity];
        mask = capacity - 1;
    }

    /** Records one occurrence of the word stored in {@code buf[from, from + len)}. */
    void add(byte[] buf, int from, int len, int hash) {
        int slot = mix(hash) & mask;
        while (true) {
            int off = offsets[slot];
            if (off < 0) {
                insert(slot, buf, from, len, hash);
                return;
            }
            if (hashes[slot] == hash && lengths[slot] == len
                    && Arrays.equals(arena, off, off + len, buf, from, from + len)) {
                counts[slot]++;
                return;
            }
            slot = (slot + 1) & mask;
        }
    }

    private void insert(int slot, byte[] buf, int from, int len, int hash) {
        if (arenaSize + len > arena.length) {
            long needed = (long) arenaSize + len;
            long grown = Math.max(needed, (long) arena.length * 2);
            if (grown > Integer.MAX_VALUE - 8) {
                grown = Integer.MAX_VALUE - 8;
            }
            arena = Arrays.copyOf(arena, (int) grown);
        }
        System.arraycopy(buf, from, arena, arenaSize, len);
        offsets[slot] = arenaSize;
        lengths[slot] = len;
        hashes[slot] = hash;
        counts[slot] = 1;
        arenaSize += len;
        if (++size * 2 > offsets.length) {
            rehash();
        }
    }

    private void rehash() {
        int[] oldOffsets = offsets;
        int[] oldLengths = lengths;
        int[] oldHashes = hashes;
        long[] oldCounts = counts;
        allocate(oldOffsets.length * 2);
        for (int i = 0; i < oldOffsets.length; i++) {
            if (oldOffsets[i] < 0) {
                continue;
            }
            int slot = mix(oldHashes[i]) & mask;
            while (offsets[slot] >= 0) {
                slot = (slot + 1) & mask;
            }
            offsets[slot] = oldOffsets[i];
            lengths[slot] = oldLengths[i];
            hashes[slot] = oldHashes[i];
            counts[slot] = oldCounts[i];
        }
    }

    private static int mix(int h) {
        h *= 0x9E3779B9;
        return h ^ (h >>> 16);
    }

    /** Returns the {@code limit} most frequent words, by count descending then word ascending. */
    List<Entry> top(int limit) {
        Comparator<Integer> order = this::compareSlots;
        // Max-heap of the worst kept entry at the head.
        PriorityQueue<Integer> heap = new PriorityQueue<>(limit + 1, order.reversed());
        for (int slot = 0; slot < offsets.length; slot++) {
            if (offsets[slot] < 0) {
                continue;
            }
            if (heap.size() < limit) {
                heap.add(slot);
            } else if (limit > 0 && compareSlots(slot, heap.peek()) < 0) {
                heap.poll();
                heap.add(slot);
            }
        }
        List<Integer> slots = new ArrayList<>(heap);
        slots.sort(order);
        List<Entry> result = new ArrayList<>(slots.size());
        for (int slot : slots) {
            String word = new String(arena, offsets[slot], lengths[slot], StandardCharsets.US_ASCII);
            result.add(new Entry(word, counts[slot]));
        }
        return result;
    }

    /** Orders slots so that "better" (more frequent, then lexicographically smaller) comes first. */
    private int compareSlots(int a, int b) {
        int byCount = Long.compare(counts[b], counts[a]);
        if (byCount != 0) {
            return byCount;
        }
        return Arrays.compareUnsigned(arena, offsets[a], offsets[a] + lengths[a],
                arena, offsets[b], offsets[b] + lengths[b]);
    }
}
