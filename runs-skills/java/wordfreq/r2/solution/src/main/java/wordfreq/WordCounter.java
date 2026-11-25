package wordfreq;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.PriorityQueue;

/// Counts lowercase ASCII words fed as raw bytes, without allocating per word.
///
/// Words are stored once in a byte arena and indexed by an open-addressing hash table.
/// Input may be supplied in arbitrary chunks; a word split across chunks is joined.
final class WordCounter {

  private static final int INITIAL_CAPACITY = 1 << 12;
  private static final int MAX_WORD_HINT = 64;

  // Per-slot data; a slot is empty when lengths[slot] == 0.
  private int[] offsets = new int[INITIAL_CAPACITY];
  private int[] lengths = new int[INITIAL_CAPACITY];
  private int[] hashes = new int[INITIAL_CAPACITY];
  private long[] counts = new long[INITIAL_CAPACITY];
  private int size;

  private byte[] arena = new byte[1 << 16];
  private int arenaUsed;

  // The word currently being scanned, possibly spanning chunk boundaries.
  private byte[] current = new byte[MAX_WORD_HINT];
  private int currentLength;
  private int currentHash;

  /// Feeds `length` bytes of `buf` starting at `from`.
  void accept(byte[] buf, int from, int length) {
    int end = from + length;
    for (int i = from; i < end; i++) {
      int b = buf[i];
      int lower = b | 0x20;
      if (lower >= 'a' && lower <= 'z') {
        if (currentLength == current.length) {
          current = Arrays.copyOf(current, current.length * 2);
        }
        current[currentLength++] = (byte) lower;
        currentHash = currentHash * 31 + lower;
      } else if (currentLength > 0) {
        endWord();
      }
    }
  }

  /// Flushes a word that ends at end of input.
  void finish() {
    if (currentLength > 0) {
      endWord();
    }
  }

  /// Returns up to `limit` words ordered by [WordCount#BY_FREQUENCY].
  List<WordCount> top(int limit) {
    if (limit <= 0) {
      return List.of();
    }
    // Min-heap on the ranking order: the head is the weakest of the kept candidates.
    var heap = new PriorityQueue<WordCount>(limit + 1, WordCount.BY_FREQUENCY.reversed());
    for (int slot = 0; slot < lengths.length; slot++) {
      if (lengths[slot] == 0) {
        continue;
      }
      if (heap.size() == limit && counts[slot] < heap.peek().count()) {
        continue; // cannot beat the current minimum; skip String allocation
      }
      heap.add(new WordCount(wordAt(slot), counts[slot]));
      if (heap.size() > limit) {
        heap.poll();
      }
    }
    var result = new ArrayList<>(heap);
    result.sort(WordCount.BY_FREQUENCY);
    return result;
  }

  private String wordAt(int slot) {
    return new String(arena, offsets[slot], lengths[slot], StandardCharsets.US_ASCII);
  }

  private void endWord() {
    int hash = mix(currentHash);
    int mask = lengths.length - 1;
    int slot = hash & mask;
    while (lengths[slot] != 0) {
      if (hashes[slot] == hash && matches(slot)) {
        counts[slot]++;
        resetCurrent();
        return;
      }
      slot = (slot + 1) & mask;
    }
    insert(slot, hash);
    resetCurrent();
    if (size * 2 > lengths.length) {
      grow();
    }
  }

  private boolean matches(int slot) {
    int offset = offsets[slot];
    return lengths[slot] == currentLength
        && Arrays.equals(arena, offset, offset + currentLength, current, 0, currentLength);
  }

  private void insert(int slot, int hash) {
    if (arenaUsed + currentLength > arena.length) {
      arena = Arrays.copyOf(arena, Math.max(arena.length * 2, arenaUsed + currentLength));
    }
    System.arraycopy(current, 0, arena, arenaUsed, currentLength);
    offsets[slot] = arenaUsed;
    lengths[slot] = currentLength;
    hashes[slot] = hash;
    counts[slot] = 1;
    arenaUsed += currentLength;
    size++;
  }

  private void resetCurrent() {
    currentLength = 0;
    currentHash = 0;
  }

  private void grow() {
    int[] oldOffsets = offsets;
    int[] oldLengths = lengths;
    int[] oldHashes = hashes;
    long[] oldCounts = counts;
    int capacity = oldLengths.length * 2;
    int mask = capacity - 1;
    offsets = new int[capacity];
    lengths = new int[capacity];
    hashes = new int[capacity];
    counts = new long[capacity];
    for (int old = 0; old < oldLengths.length; old++) {
      if (oldLengths[old] == 0) {
        continue;
      }
      int slot = oldHashes[old] & mask;
      while (lengths[slot] != 0) {
        slot = (slot + 1) & mask;
      }
      offsets[slot] = oldOffsets[old];
      lengths[slot] = oldLengths[old];
      hashes[slot] = oldHashes[old];
      counts[slot] = oldCounts[old];
    }
  }

  private static int mix(int h) {
    h *= 0x9E3779B9;
    return h ^ (h >>> 16);
  }
}
