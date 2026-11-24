package wordfreq;

import java.util.Arrays;

/**
 * Counts occurrences of byte-string words using an open-addressing hash table.
 * Word bytes are stored contiguously in a single arena to avoid per-word allocation.
 */
final class WordCounter {

    /** A word together with its occurrence count. */
    record Entry(String word, int count) {
    }

    private static final int INITIAL_CAPACITY = 1 << 12;

    private byte[] arena = new byte[1 << 16];
    private int arenaSize;

    // Per-entry columns, indexed by entry id.
    private int[] offsets = new int[INITIAL_CAPACITY];
    private int[] lengths = new int[INITIAL_CAPACITY];
    private int[] hashes = new int[INITIAL_CAPACITY];
    private int[] counts = new int[INITIAL_CAPACITY];
    private int size;

    // Hash slots hold entry id + 1; zero marks an empty slot.
    private int[] slots = new int[INITIAL_CAPACITY * 2];
    private int mask = slots.length - 1;

    /** Records one occurrence of {@code word[0..length)}. */
    void add(byte[] word, int length) {
        int hash = hash(word, length);
        int slot = hash & mask;
        while (true) {
            int id = slots[slot] - 1;
            if (id < 0) {
                insert(slot, word, length, hash);
                return;
            }
            if (hashes[id] == hash && matches(id, word, length)) {
                counts[id]++;
                return;
            }
            slot = (slot + 1) & mask;
        }
    }

    /** Returns the {@code limit} most frequent words, by count descending then word ascending. */
    Entry[] top(int limit) {
        Integer[] ids = new Integer[size];
        for (int i = 0; i < size; i++) {
            ids[i] = i;
        }
        Arrays.sort(ids, this::compareIds);
        int n = Math.min(limit, size);
        Entry[] result = new Entry[n];
        for (int i = 0; i < n; i++) {
            int id = ids[i];
            result[i] = new Entry(new String(arena, offsets[id], lengths[id], java.nio.charset.StandardCharsets.ISO_8859_1),
                    counts[id]);
        }
        return result;
    }

    private int compareIds(int a, int b) {
        int byCount = Integer.compare(counts[b], counts[a]);
        if (byCount != 0) {
            return byCount;
        }
        return Arrays.compareUnsigned(arena, offsets[a], offsets[a] + lengths[a],
                arena, offsets[b], offsets[b] + lengths[b]);
    }

    private boolean matches(int id, byte[] word, int length) {
        int offset = offsets[id];
        return lengths[id] == length && Arrays.equals(arena, offset, offset + length, word, 0, length);
    }

    private void insert(int slot, byte[] word, int length, int hash) {
        if (size == offsets.length) {
            growEntries();
        }
        ensureArena(length);
        System.arraycopy(word, 0, arena, arenaSize, length);
        int id = size++;
        offsets[id] = arenaSize;
        lengths[id] = length;
        hashes[id] = hash;
        counts[id] = 1;
        arenaSize += length;
        slots[slot] = id + 1;
        if (size * 2 > slots.length) {
            rehash();
        }
    }

    private void ensureArena(int extra) {
        long needed = (long) arenaSize + extra;
        if (needed > arena.length) {
            long grown = Math.max(needed, (long) arena.length * 2);
            arena = Arrays.copyOf(arena, (int) Math.min(grown, Integer.MAX_VALUE - 8));
        }
    }

    private void growEntries() {
        int capacity = offsets.length * 2;
        offsets = Arrays.copyOf(offsets, capacity);
        lengths = Arrays.copyOf(lengths, capacity);
        hashes = Arrays.copyOf(hashes, capacity);
        counts = Arrays.copyOf(counts, capacity);
    }

    private void rehash() {
        slots = new int[slots.length * 2];
        mask = slots.length - 1;
        for (int id = 0; id < size; id++) {
            int slot = hashes[id] & mask;
            while (slots[slot] != 0) {
                slot = (slot + 1) & mask;
            }
            slots[slot] = id + 1;
        }
    }

    private static int hash(byte[] word, int length) {
        int h = 0x811C9DC5;
        for (int i = 0; i < length; i++) {
            h = (h ^ word[i]) * 0x01000193;
        }
        return h ^ (h >>> 16);
    }
}
