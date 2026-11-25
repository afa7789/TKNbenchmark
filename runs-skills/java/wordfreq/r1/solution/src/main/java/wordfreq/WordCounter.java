package wordfreq;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.PriorityQueue;

/// Counts occurrences of byte-string words using an open-addressing hash table.
///
/// Word bytes are copied into a single growable arena so that the table itself holds
/// only primitive arrays, which keeps memory use and GC pressure low for large inputs.
final class WordCounter {

    /// A word and the number of times it was seen.
    record Entry(String word, int count) {}

    private static final int INITIAL_CAPACITY = 1 << 12;
    private static final Comparator<Entry> RANKING =
            Comparator.comparingInt(Entry::count).reversed().thenComparing(Entry::word);

    private int[] slots;        // index into the entry arrays + 1; 0 means empty
    private int[] hashes;
    private int[] offsets;
    private int[] lengths;
    private int[] counts;
    private byte[] arena = new byte[1 << 16];
    private int arenaSize;
    private int size;

    WordCounter() {
        slots = new int[INITIAL_CAPACITY];
        int entries = INITIAL_CAPACITY / 2;
        hashes = new int[entries];
        offsets = new int[entries];
        lengths = new int[entries];
        counts = new int[entries];
    }

    /// Records one occurrence of the word stored in `buf[0, len)`.
    void add(byte[] buf, int len) {
        int hash = hash(buf, len);
        int mask = slots.length - 1;
        for (int i = hash & mask; ; i = (i + 1) & mask) {
            int slot = slots[i];
            if (slot == 0) {
                insert(i, hash, buf, len);
                return;
            }
            int e = slot - 1;
            if (hashes[e] == hash && lengths[e] == len
                    && Arrays.equals(arena, offsets[e], offsets[e] + len, buf, 0, len)) {
                counts[e]++;
                return;
            }
        }
    }

    /// Returns the `limit` most frequent words, by count descending then word ascending.
    List<Entry> top(int limit) {
        PriorityQueue<Entry> heap = new PriorityQueue<>(limit + 1, RANKING.reversed());
        for (int e = 0; e < size; e++) {
            if (heap.size() == limit) {
                Entry worst = heap.peek();
                if (counts[e] < worst.count()) {
                    continue;
                }
                Entry candidate = entry(e);
                if (RANKING.compare(candidate, worst) >= 0) {
                    continue;
                }
                heap.poll();
                heap.add(candidate);
            } else {
                heap.add(entry(e));
            }
        }
        List<Entry> result = new ArrayList<>(heap);
        result.sort(RANKING);
        return result;
    }

    private Entry entry(int e) {
        return new Entry(new String(arena, offsets[e], lengths[e], StandardCharsets.US_ASCII), counts[e]);
    }

    private void insert(int slotIndex, int hash, byte[] buf, int len) {
        if (size == counts.length) {
            growEntries();
        }
        if (arenaSize + len > arena.length) {
            arena = Arrays.copyOf(arena, Math.max(arena.length * 2, arenaSize + len));
        }
        System.arraycopy(buf, 0, arena, arenaSize, len);
        int e = size++;
        hashes[e] = hash;
        offsets[e] = arenaSize;
        lengths[e] = len;
        counts[e] = 1;
        arenaSize += len;
        slots[slotIndex] = e + 1;
        if (size * 2 > slots.length) {
            rehash();
        }
    }

    private void growEntries() {
        int n = counts.length * 2;
        hashes = Arrays.copyOf(hashes, n);
        offsets = Arrays.copyOf(offsets, n);
        lengths = Arrays.copyOf(lengths, n);
        counts = Arrays.copyOf(counts, n);
    }

    private void rehash() {
        int[] next = new int[slots.length * 2];
        int mask = next.length - 1;
        for (int e = 0; e < size; e++) {
            int i = hashes[e] & mask;
            while (next[i] != 0) {
                i = (i + 1) & mask;
            }
            next[i] = e + 1;
        }
        slots = next;
    }

    private static int hash(byte[] buf, int len) {
        int h = 0x811c9dc5;
        for (int i = 0; i < len; i++) {
            h = (h ^ buf[i]) * 0x01000193;
        }
        return h ^ (h >>> 16);
    }
}
