package wordfreq;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.PriorityQueue;

/// Counts occurrences of byte-string words using an open-addressing hash table.
///
/// Word bytes are stored once in a shared arena, so counting does not allocate per occurrence.
final class WordCounter {

    private static final int INITIAL_CAPACITY = 1 << 14;

    /// Slot table: 0 means empty, otherwise entry index + 1.
    private int[] slots = new int[INITIAL_CAPACITY];
    private int mask = INITIAL_CAPACITY - 1;

    private int[] offsets = new int[INITIAL_CAPACITY / 2];
    private int[] lengths = new int[INITIAL_CAPACITY / 2];
    private int[] hashes = new int[INITIAL_CAPACITY / 2];
    private long[] counts = new long[INITIAL_CAPACITY / 2];
    private int size;

    private byte[] arena = new byte[1 << 16];
    private int arenaSize;

    /// Records one occurrence of the word stored in `buf[0, len)`, whose hash is `hash`.
    void add(byte[] buf, int len, int hash) {
        int slot = hash & mask;
        while (true) {
            int entry = slots[slot] - 1;
            if (entry < 0) {
                insert(slot, buf, len, hash);
                return;
            }
            if (hashes[entry] == hash && lengths[entry] == len
                    && Arrays.equals(arena, offsets[entry], offsets[entry] + len, buf, 0, len)) {
                counts[entry]++;
                return;
            }
            slot = (slot + 1) & mask;
        }
    }

    /// Mixes the raw rolling hash so that low bits are well distributed.
    static int finishHash(int h) {
        h ^= h >>> 16;
        h *= 0x85ebca6b;
        h ^= h >>> 13;
        return h;
    }

    private void insert(int slot, byte[] buf, int len, int hash) {
        if (size == offsets.length) {
            int n = size * 2;
            offsets = Arrays.copyOf(offsets, n);
            lengths = Arrays.copyOf(lengths, n);
            hashes = Arrays.copyOf(hashes, n);
            counts = Arrays.copyOf(counts, n);
        }
        if (arenaSize + len > arena.length) {
            arena = Arrays.copyOf(arena, Math.max(arena.length * 2, arenaSize + len));
        }
        System.arraycopy(buf, 0, arena, arenaSize, len);
        offsets[size] = arenaSize;
        lengths[size] = len;
        hashes[size] = hash;
        counts[size] = 1;
        arenaSize += len;
        slots[slot] = ++size;
        if (size * 2 > slots.length) {
            rehash();
        }
    }

    private void rehash() {
        int[] grown = new int[slots.length * 2];
        int newMask = grown.length - 1;
        for (int e = 0; e < size; e++) {
            int slot = hashes[e] & newMask;
            while (grown[slot] != 0) {
                slot = (slot + 1) & newMask;
            }
            grown[slot] = e + 1;
        }
        slots = grown;
        mask = newMask;
    }

    /// Returns up to `limit` words ordered by count descending, then by word bytes ascending.
    List<WordCount> top(int limit) {
        Comparator<Integer> order = this::compareEntries;
        // Max-heap on the reversed order keeps the worst retained entry at the head.
        PriorityQueue<Integer> heap = new PriorityQueue<>(limit + 1, order.reversed());
        for (int e = 0; e < size; e++) {
            if (heap.size() < limit) {
                heap.add(e);
            } else if (limit > 0 && compareEntries(e, heap.peek()) < 0) {
                heap.poll();
                heap.add(e);
            }
        }
        List<Integer> best = new ArrayList<>(heap);
        best.sort(order);
        List<WordCount> result = new ArrayList<>(best.size());
        for (int e : best) {
            result.add(new WordCount(Arrays.copyOfRange(arena, offsets[e], offsets[e] + lengths[e]), counts[e]));
        }
        return result;
    }

    private int compareEntries(int a, int b) {
        int byCount = Long.compare(counts[b], counts[a]);
        if (byCount != 0) {
            return byCount;
        }
        return Arrays.compareUnsigned(arena, offsets[a], offsets[a] + lengths[a],
                arena, offsets[b], offsets[b] + lengths[b]);
    }
}
