/** A word together with its occurrence count. */
export interface Entry {
  readonly word: string;
  readonly count: number;
}

const INITIAL_CAPACITY = 1 << 12;
const INITIAL_ARENA = 1 << 16;

function growInt32(array: Int32Array, capacity: number): Int32Array {
  const grown = new Int32Array(capacity);
  grown.set(array);
  return grown;
}

/** FNV-1a over `word[0..length)`, with the high bits folded into the low ones. */
function hashBytes(word: Uint8Array, length: number): number {
  let h = 0x811c9dc5 | 0;
  for (let i = 0; i < length; i++) {
    h = Math.imul(h ^ word[i], 0x01000193);
  }
  return h ^ (h >>> 16);
}

/**
 * Counts occurrences of byte-string words using an open-addressing hash table.
 * Word bytes are stored contiguously in a single arena to avoid per-word allocation.
 */
export class WordCounter {
  #arena = new Uint8Array(INITIAL_ARENA);
  #arenaSize = 0;

  // Per-entry columns, indexed by entry id.
  #offsets = new Int32Array(INITIAL_CAPACITY);
  #lengths = new Int32Array(INITIAL_CAPACITY);
  #hashes = new Int32Array(INITIAL_CAPACITY);
  #counts = new Int32Array(INITIAL_CAPACITY);
  #size = 0;

  // Hash slots hold entry id + 1; zero marks an empty slot.
  #slots = new Int32Array(INITIAL_CAPACITY * 2);
  #mask = this.#slots.length - 1;

  /** Number of distinct words seen so far. */
  get size(): number {
    return this.#size;
  }

  /** Records one occurrence of `word[0..length)`. */
  add(word: Uint8Array, length: number): void {
    const hash = hashBytes(word, length);
    const slots = this.#slots;
    const mask = this.#mask;
    let slot = hash & mask;
    for (;;) {
      const id = slots[slot] - 1;
      if (id < 0) {
        this.#insert(slot, word, length, hash);
        return;
      }
      if (this.#hashes[id] === hash && this.#matches(id, word, length)) {
        this.#counts[id]++;
        return;
      }
      slot = (slot + 1) & mask;
    }
  }

  /** Returns the `limit` most frequent words, by count descending then word ascending. */
  top(limit: number): Entry[] {
    const ids = Array.from({ length: this.#size }, (_, i) => i);
    ids.sort((a, b) => this.#compareIds(a, b));
    const decoder = new TextDecoder('latin1');
    return ids.slice(0, Math.min(limit, this.#size)).map((id) => ({
      word: decoder.decode(this.#wordBytes(id)),
      count: this.#counts[id],
    }));
  }

  #wordBytes(id: number): Uint8Array {
    const offset = this.#offsets[id];
    return this.#arena.subarray(offset, offset + this.#lengths[id]);
  }

  #compareIds(a: number, b: number): number {
    const byCount = this.#counts[b] - this.#counts[a];
    if (byCount !== 0) {
      return byCount;
    }
    return Buffer.compare(this.#wordBytes(a), this.#wordBytes(b));
  }

  #matches(id: number, word: Uint8Array, length: number): boolean {
    if (this.#lengths[id] !== length) {
      return false;
    }
    const arena = this.#arena;
    const offset = this.#offsets[id];
    for (let i = 0; i < length; i++) {
      if (arena[offset + i] !== word[i]) {
        return false;
      }
    }
    return true;
  }

  #insert(slot: number, word: Uint8Array, length: number, hash: number): void {
    if (this.#size === this.#offsets.length) {
      this.#growEntries();
    }
    this.#ensureArena(length);
    this.#arena.set(word.subarray(0, length), this.#arenaSize);
    const id = this.#size++;
    this.#offsets[id] = this.#arenaSize;
    this.#lengths[id] = length;
    this.#hashes[id] = hash;
    this.#counts[id] = 1;
    this.#arenaSize += length;
    this.#slots[slot] = id + 1;
    if (this.#size * 2 > this.#slots.length) {
      this.#rehash();
    }
  }

  #ensureArena(extra: number): void {
    const needed = this.#arenaSize + extra;
    if (needed > this.#arena.length) {
      const grown = new Uint8Array(Math.max(needed, this.#arena.length * 2));
      grown.set(this.#arena.subarray(0, this.#arenaSize));
      this.#arena = grown;
    }
  }

  #growEntries(): void {
    const capacity = this.#offsets.length * 2;
    this.#offsets = growInt32(this.#offsets, capacity);
    this.#lengths = growInt32(this.#lengths, capacity);
    this.#hashes = growInt32(this.#hashes, capacity);
    this.#counts = growInt32(this.#counts, capacity);
  }

  #rehash(): void {
    const slots = new Int32Array(this.#slots.length * 2);
    const mask = slots.length - 1;
    for (let id = 0; id < this.#size; id++) {
      let slot = this.#hashes[id] & mask;
      while (slots[slot] !== 0) {
        slot = (slot + 1) & mask;
      }
      slots[slot] = id + 1;
    }
    this.#slots = slots;
    this.#mask = mask;
  }
}
