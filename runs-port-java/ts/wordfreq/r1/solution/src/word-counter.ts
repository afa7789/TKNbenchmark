/** A word together with its occurrence count. */
export interface Entry {
  readonly word: string;
  readonly count: number;
}

const INITIAL_CAPACITY = 1 << 12;
const INITIAL_ARENA = 1 << 16;
const EMPTY = -1;

/** Scrambles a word hash so that linear probing spreads keys evenly. */
function mix(hash: number): number {
  const h = Math.imul(hash, 0x9e3779b9);
  return h ^ (h >>> 16);
}

/** Lexicographic comparison of two byte ranges, treating bytes as unsigned. */
function compareBytes(a: Uint8Array, aFrom: number, aLen: number, b: Uint8Array, bFrom: number, bLen: number): number {
  const n = Math.min(aLen, bLen);
  for (let i = 0; i < n; i++) {
    const d = a[aFrom + i] - b[bFrom + i];
    if (d !== 0) return d;
  }
  return aLen - bLen;
}

/**
 * Counts occurrences of byte-string words using an open-addressing hash table.
 * Word bytes are stored contiguously in an arena to avoid per-word allocations.
 */
export class WordCounter {
  #arena = new Uint8Array(INITIAL_ARENA);
  #arenaSize = 0;

  // Per-slot data; a slot is empty when offsets[slot] === EMPTY.
  #offsets!: Int32Array;
  #lengths!: Int32Array;
  #hashes!: Int32Array;
  #counts!: Float64Array;
  #size = 0;
  #mask = 0;

  constructor() {
    this.#allocate(INITIAL_CAPACITY);
  }

  /** Number of distinct words recorded. */
  get size(): number {
    return this.#size;
  }

  #allocate(capacity: number): void {
    this.#offsets = new Int32Array(capacity).fill(EMPTY);
    this.#lengths = new Int32Array(capacity);
    this.#hashes = new Int32Array(capacity);
    this.#counts = new Float64Array(capacity);
    this.#mask = capacity - 1;
  }

  /**
   * Records one occurrence of the word stored in `buf[from, from + len)`.
   * `hash` must be the polynomial (×31) hash of those bytes, as a 32-bit integer.
   */
  add(buf: Uint8Array, from: number, len: number, hash: number): void {
    const offsets = this.#offsets;
    const arena = this.#arena;
    let slot = mix(hash) & this.#mask;
    for (;;) {
      const off = offsets[slot];
      if (off === EMPTY) {
        this.#insert(slot, buf, from, len, hash);
        return;
      }
      if (
        this.#hashes[slot] === hash &&
        this.#lengths[slot] === len &&
        compareBytes(arena, off, len, buf, from, len) === 0
      ) {
        this.#counts[slot]++;
        return;
      }
      slot = (slot + 1) & this.#mask;
    }
  }

  #insert(slot: number, buf: Uint8Array, from: number, len: number, hash: number): void {
    const needed = this.#arenaSize + len;
    if (needed > this.#arena.length) {
      const grown = new Uint8Array(Math.max(needed, this.#arena.length * 2));
      grown.set(this.#arena.subarray(0, this.#arenaSize));
      this.#arena = grown;
    }
    this.#arena.set(buf.subarray(from, from + len), this.#arenaSize);
    this.#offsets[slot] = this.#arenaSize;
    this.#lengths[slot] = len;
    this.#hashes[slot] = hash;
    this.#counts[slot] = 1;
    this.#arenaSize = needed;
    if (++this.#size * 2 > this.#offsets.length) {
      this.#rehash();
    }
  }

  #rehash(): void {
    const oldOffsets = this.#offsets;
    const oldLengths = this.#lengths;
    const oldHashes = this.#hashes;
    const oldCounts = this.#counts;
    this.#allocate(oldOffsets.length * 2);
    const offsets = this.#offsets;
    const mask = this.#mask;
    for (let i = 0; i < oldOffsets.length; i++) {
      if (oldOffsets[i] === EMPTY) continue;
      let slot = mix(oldHashes[i]) & mask;
      while (offsets[slot] !== EMPTY) {
        slot = (slot + 1) & mask;
      }
      offsets[slot] = oldOffsets[i];
      this.#lengths[slot] = oldLengths[i];
      this.#hashes[slot] = oldHashes[i];
      this.#counts[slot] = oldCounts[i];
    }
  }

  /** Orders slots so that "better" (more frequent, then byte-wise smaller) comes first. */
  #compareSlots(a: number, b: number): number {
    const byCount = this.#counts[b] - this.#counts[a];
    if (byCount !== 0) return byCount;
    return compareBytes(
      this.#arena, this.#offsets[a], this.#lengths[a],
      this.#arena, this.#offsets[b], this.#lengths[b],
    );
  }

  /** Returns the `limit` most frequent words, by count descending then word ascending. */
  top(limit: number): Entry[] {
    if (limit <= 0) return [];
    const compare = (a: number, b: number): number => this.#compareSlots(a, b);

    // Kept sorted best-first; the worst kept slot is last. `limit` is small,
    // so insertion into a short sorted array beats a heap in practice.
    const kept: number[] = [];
    const offsets = this.#offsets;
    for (let slot = 0; slot < offsets.length; slot++) {
      if (offsets[slot] === EMPTY) continue;
      if (kept.length === limit) {
        if (compare(slot, kept[limit - 1]) >= 0) continue;
        kept.pop();
      }
      let i = kept.length;
      while (i > 0 && compare(slot, kept[i - 1]) < 0) i--;
      kept.splice(i, 0, slot);
    }

    const decoder = new TextDecoder("latin1");
    return kept.map((slot) => ({
      word: decoder.decode(this.#arena.subarray(offsets[slot], offsets[slot] + this.#lengths[slot])),
      count: this.#counts[slot],
    }));
  }
}
