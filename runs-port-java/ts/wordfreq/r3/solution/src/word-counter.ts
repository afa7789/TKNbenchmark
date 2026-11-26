/** A word together with its occurrence count. */
export interface WordCount {
  readonly word: string;
  readonly count: number;
}

const EMPTY = -1;
const MAX_LOAD = 0.5;
const INITIAL_SLOTS = 1 << 12;
const INITIAL_ENTRIES = 1024;
const INITIAL_ARENA = 1 << 16;

function grow<T extends Int32Array | Uint8Array>(array: T, capacity: number): T {
  const grown = new (array.constructor as new (length: number) => T)(capacity);
  grown.set(array);
  return grown;
}

/**
 * Counts occurrences of byte-string words using an open-addressing hash table.
 * Word bytes are stored contiguously in a single arena to avoid per-word allocation.
 */
export class WordCounter {
  #slots = new Int32Array(INITIAL_SLOTS).fill(EMPTY);
  #mask = INITIAL_SLOTS - 1;

  #size = 0;
  #hashes = new Int32Array(INITIAL_ENTRIES);
  #offsets = new Int32Array(INITIAL_ENTRIES);
  #lengths = new Int32Array(INITIAL_ENTRIES);
  #counts = new Int32Array(INITIAL_ENTRIES);

  #arena = new Uint8Array(INITIAL_ARENA);
  #arenaUsed = 0;

  /** Number of distinct words recorded. */
  get size(): number {
    return this.#size;
  }

  /** Records one occurrence of the word stored in `buf[0..len)`. */
  add(buf: Uint8Array, len: number): void {
    const hash = WordCounter.#hash(buf, len);
    const slots = this.#slots;
    const mask = this.#mask;
    let slot = hash & mask;
    for (;;) {
      const entry = slots[slot];
      if (entry === EMPTY) {
        this.#insert(slot, hash, buf, len);
        return;
      }
      if (this.#hashes[entry] === hash && this.#lengths[entry] === len && this.#matches(entry, buf, len)) {
        this.#counts[entry]++;
        return;
      }
      slot = (slot + 1) & mask;
    }
  }

  /** Returns up to `limit` words ordered by count descending, then word ascending. */
  top(limit: number): WordCount[] {
    if (limit <= 0) return [];
    // Keep a small sorted list of the best entries; limit is tiny so insertion is cheap.
    const best: number[] = [];
    for (let entry = 0; entry < this.#size; entry++) {
      if (best.length === limit && this.#compareEntries(entry, best[limit - 1]) >= 0) continue;
      let at = best.length;
      while (at > 0 && this.#compareEntries(entry, best[at - 1]) < 0) at--;
      best.splice(at, 0, entry);
      if (best.length > limit) best.pop();
    }
    const decoder = new TextDecoder('latin1');
    return best.map((entry) => ({
      word: decoder.decode(this.#arena.subarray(this.#offsets[entry], this.#offsets[entry] + this.#lengths[entry])),
      count: this.#counts[entry],
    }));
  }

  #matches(entry: number, buf: Uint8Array, len: number): boolean {
    const arena = this.#arena;
    const offset = this.#offsets[entry];
    for (let i = 0; i < len; i++) {
      if (arena[offset + i] !== buf[i]) return false;
    }
    return true;
  }

  #compareEntries(a: number, b: number): number {
    const byCount = this.#counts[b] - this.#counts[a];
    if (byCount !== 0) return byCount;
    const arena = this.#arena;
    const offA = this.#offsets[a];
    const offB = this.#offsets[b];
    const lenA = this.#lengths[a];
    const lenB = this.#lengths[b];
    const common = Math.min(lenA, lenB);
    for (let i = 0; i < common; i++) {
      const diff = arena[offA + i] - arena[offB + i];
      if (diff !== 0) return diff;
    }
    return lenA - lenB;
  }

  #insert(slot: number, hash: number, buf: Uint8Array, len: number): void {
    if (this.#size === this.#counts.length) {
      const capacity = this.#size * 2;
      this.#hashes = grow(this.#hashes, capacity);
      this.#offsets = grow(this.#offsets, capacity);
      this.#lengths = grow(this.#lengths, capacity);
      this.#counts = grow(this.#counts, capacity);
    }
    this.#ensureArenaCapacity(len);
    this.#arena.set(buf.subarray(0, len), this.#arenaUsed);

    const entry = this.#size++;
    this.#hashes[entry] = hash;
    this.#offsets[entry] = this.#arenaUsed;
    this.#lengths[entry] = len;
    this.#counts[entry] = 1;
    this.#arenaUsed += len;
    this.#slots[slot] = entry;

    if (this.#size > this.#slots.length * MAX_LOAD) this.#rehash();
  }

  #ensureArenaCapacity(extra: number): void {
    const required = this.#arenaUsed + extra;
    if (required > this.#arena.length) {
      this.#arena = grow(this.#arena, Math.max(required, this.#arena.length * 2));
    }
  }

  #rehash(): void {
    const grown = new Int32Array(this.#slots.length * 2).fill(EMPTY);
    const newMask = grown.length - 1;
    for (let entry = 0; entry < this.#size; entry++) {
      let slot = this.#hashes[entry] & newMask;
      while (grown[slot] !== EMPTY) slot = (slot + 1) & newMask;
      grown[slot] = entry;
    }
    this.#slots = grown;
    this.#mask = newMask;
  }

  static #hash(buf: Uint8Array, len: number): number {
    // FNV-1a followed by a finalizer so low bits are well mixed for masking.
    let h = 0x811c9dc5 | 0;
    for (let i = 0; i < len; i++) h = Math.imul(h ^ buf[i], 0x01000193);
    h ^= h >>> 16;
    h = Math.imul(h, 0x85ebca6b);
    h ^= h >>> 13;
    return h;
  }
}
