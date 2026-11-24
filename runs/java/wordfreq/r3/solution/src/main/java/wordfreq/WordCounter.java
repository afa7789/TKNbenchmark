package wordfreq;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.PriorityQueue;

/**
 * Counts occurrences of byte-string words using an open-addressing hash table.
 * Word bytes are stored contiguously in a single arena to avoid per-word allocation.
 */
final class WordCounter {

    /** A word together with its occurrence count. */
    record WordCount(String word, int count) {
    }

    private static final int EMPTY = -1;
    private static final double MAX_LOAD = 0.5;

    private int[] slots;
    private int mask;

    private int size;
    private int[] hashes = new int[1024];
    private int[] offsets = new int[1024];
    private int[] lengths = new int[1024];
    private int[] counts = new int[1024];

    private byte[] arena = new byte[1 << 16];
    private int arenaUsed;

    WordCounter() {
        slots = new int[1 << 12];
        Arrays.fill(slots, EMPTY);
        mask = slots.length - 1;
    }

    /** Records one occurrence of the word stored in {@code buf[0..len)}. */
    void add(byte[] buf, int len) {
        int hash = hash(buf, len);
        int slot = hash & mask;
        while (true) {
            int entry = slots[slot];
            if (entry == EMPTY) {
                insert(slot, hash, buf, len);
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

    /** Returns up to {@code limit} words ordered by count descending, then word ascending. */
    List<WordCount> top(int limit) {
        if (limit <= 0) {
            return List.of();
        }
        Comparator<Integer> rank = this::compareEntries;
        // Max-heap on rank so the worst retained entry is at the head.
        PriorityQueue<Integer> heap = new PriorityQueue<>(limit + 1, rank.reversed());
        for (int i = 0; i < size; i++) {
            if (heap.size() < limit) {
                heap.add(i);
            } else if (compareEntries(i, heap.peek()) < 0) {
                heap.poll();
                heap.add(i);
            }
        }
        List<Integer> best = new ArrayList<>(heap);
        best.sort(rank);
        List<WordCount> result = new ArrayList<>(best.size());
        for (int e : best) {
            String word = new String(arena, offsets[e], lengths[e], StandardCharsets.US_ASCII);
            result.add(new WordCount(word, counts[e]));
        }
        return result;
    }

    private int compareEntries(int a, int b) {
        int byCount = Integer.compare(counts[b], counts[a]);
        if (byCount != 0) {
            return byCount;
        }
        return Arrays.compareUnsigned(
                arena, offsets[a], offsets[a] + lengths[a],
                arena, offsets[b], offsets[b] + lengths[b]);
    }

    private void insert(int slot, int hash, byte[] buf, int len) {
        if (size == counts.length) {
            int capacity = size * 2;
            hashes = Arrays.copyOf(hashes, capacity);
            offsets = Arrays.copyOf(offsets, capacity);
            lengths = Arrays.copyOf(lengths, capacity);
            counts = Arrays.copyOf(counts, capacity);
        }
        ensureArenaCapacity(len);
        System.arraycopy(buf, 0, arena, arenaUsed, len);

        int entry = size++;
        hashes[entry] = hash;
        offsets[entry] = arenaUsed;
        lengths[entry] = len;
        counts[entry] = 1;
        arenaUsed += len;
        slots[slot] = entry;

        if (size > slots.length * MAX_LOAD) {
            rehash();
        }
    }

    private void ensureArenaCapacity(int extra) {
        long required = (long) arenaUsed + extra;
        if (required > arena.length) {
            long grown = Math.max(required, (long) arena.length * 2);
            arena = Arrays.copyOf(arena, (int) Math.min(grown, Integer.MAX_VALUE - 8));
        }
    }

    private void rehash() {
        int[] grown = new int[slots.length * 2];
        Arrays.fill(grown, EMPTY);
        int newMask = grown.length - 1;
        for (int entry = 0; entry < size; entry++) {
            int slot = hashes[entry] & newMask;
            while (grown[slot] != EMPTY) {
                slot = (slot + 1) & newMask;
            }
            grown[slot] = entry;
        }
        slots = grown;
        mask = newMask;
    }

    private static int hash(byte[] buf, int len) {
        // FNV-1a followed by a finalizer so low bits are well mixed for masking.
        int h = 0x811C9DC5;
        for (int i = 0; i < len; i++) {
            h = (h ^ buf[i]) * 0x01000193;
        }
        h ^= h >>> 16;
        h *= 0x85EBCA6B;
        h ^= h >>> 13;
        return h;
    }
}
