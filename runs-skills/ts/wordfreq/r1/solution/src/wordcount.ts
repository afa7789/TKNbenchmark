/**
 * Byte-level word counter.
 *
 * A word is a maximal run of ASCII letters; everything else is a separator.
 * Words are folded to lowercase and stored in an open-addressing hash table
 * whose keys live in a shared byte arena, so no per-word strings are created
 * while scanning (important for inputs of tens of megabytes).
 */

export interface WordCount {
  readonly word: string;
  readonly count: number;
}

const FNV_OFFSET = 0x811c9dc5;
const FNV_PRIME = 0x01000193;
const INITIAL_CAPACITY = 1 << 12;
const EMPTY = -1;

/** Lookup table: lowercase ASCII code for letters, 0 for separators. */
const LOWER = new Uint8Array(256);
for (let c = 0x41; c <= 0x5a; c++) LOWER[c] = c | 0x20;
for (let c = 0x61; c <= 0x7a; c++) LOWER[c] = c;

export class WordCounter {
  #capacity = INITIAL_CAPACITY;
  #mask = INITIAL_CAPACITY - 1;
  /** Slot -> entry index, or EMPTY. */
  #slots = new Int32Array(INITIAL_CAPACITY).fill(EMPTY);

  // Per-entry columns, indexed by entry id.
  #hashes = new Uint32Array(INITIAL_CAPACITY);
  #offsets = new Int32Array(INITIAL_CAPACITY);
  #lengths = new Int32Array(INITIAL_CAPACITY);
  #counts = new Float64Array(INITIAL_CAPACITY);
  #size = 0;

  /** Lowercased bytes of every distinct word, back to back. */
  #arena = new Uint8Array(1 << 16);
  #arenaUsed = 0;

  /** Scratch buffer holding the lowercased word currently being scanned. */
  #word = new Uint8Array(256);

  /** Counts every word in `data`. Words never span calls. */
  add(data: Uint8Array): void {
    const lower = LOWER;
    const n = data.length;
    let i = 0;
    while (i < n) {
      // Skip separators.
      while (i < n && lower[data[i]!] === 0) i++;
      if (i >= n) break;

      let len = 0;
      let hash = FNV_OFFSET;
      let word = this.#word;
      while (i < n) {
        const c = lower[data[i]!]!;
        if (c === 0) break;
        if (len === word.length) word = this.#growWord();
        word[len++] = c;
        hash = Math.imul(hash ^ c, FNV_PRIME);
        i++;
      }
      this.#increment(word, len, hash >>> 0);
    }
  }

  /** Returns up to `limit` words, by count descending then word ascending. */
  top(limit: number): WordCount[] {
    const best: number[] = [];
    for (let e = 0; e < this.#size; e++) {
      if (best.length === limit && !this.#ranksBefore(e, best[best.length - 1]!)) continue;
      let pos = best.length < limit ? best.length : limit - 1;
      while (pos > 0 && this.#ranksBefore(e, best[pos - 1]!)) {
        best[pos] = best[pos - 1]!;
        pos--;
      }
      best[pos] = e;
    }
    return best.map((e) => ({ word: this.#wordOf(e), count: this.#counts[e]! }));
  }

  #increment(word: Uint8Array, len: number, hash: number): void {
    const arena = this.#arena;
    let slot = hash & this.#mask;
    for (;;) {
      const e = this.#slots[slot]!;
      if (e === EMPTY) break;
      if (this.#hashes[e] === hash && this.#lengths[e] === len) {
        const off = this.#offsets[e]!;
        let k = 0;
        while (k < len && arena[off + k] === word[k]) k++;
        if (k === len) {
          this.#counts[e]!++;
          return;
        }
      }
      slot = (slot + 1) & this.#mask;
    }
    this.#insert(slot, word, len, hash);
  }

  #insert(slot: number, word: Uint8Array, len: number, hash: number): void {
    if (this.#arenaUsed + len > this.#arena.length) {
      this.#arena = grow(this.#arena, this.#arenaUsed + len);
    }
    this.#arena.set(word.subarray(0, len), this.#arenaUsed);

    const e = this.#size++;
    this.#slots[slot] = e;
    this.#hashes[e] = hash;
    this.#offsets[e] = this.#arenaUsed;
    this.#lengths[e] = len;
    this.#counts[e] = 1;
    this.#arenaUsed += len;

    // Keep the load factor at or below 1/2.
    if (this.#size * 2 > this.#capacity) this.#rehash();
  }

  #rehash(): void {
    const capacity = this.#capacity * 2;
    const mask = capacity - 1;
    const slots = new Int32Array(capacity).fill(EMPTY);
    for (let e = 0; e < this.#size; e++) {
      let slot = this.#hashes[e]! & mask;
      while (slots[slot] !== EMPTY) slot = (slot + 1) & mask;
      slots[slot] = e;
    }
    this.#capacity = capacity;
    this.#mask = mask;
    this.#slots = slots;
    this.#hashes = resize(this.#hashes, new Uint32Array(capacity));
    this.#offsets = resize(this.#offsets, new Int32Array(capacity));
    this.#lengths = resize(this.#lengths, new Int32Array(capacity));
    this.#counts = resize(this.#counts, new Float64Array(capacity));
  }

  #growWord(): Uint8Array {
    this.#word = grow(this.#word, this.#word.length + 1);
    return this.#word;
  }

  /** True when entry `a` sorts strictly before entry `b`. */
  #ranksBefore(a: number, b: number): boolean {
    const ca = this.#counts[a]!;
    const cb = this.#counts[b]!;
    if (ca !== cb) return ca > cb;
    return this.#compareWords(a, b) < 0;
  }

  #compareWords(a: number, b: number): number {
    const arena = this.#arena;
    const offA = this.#offsets[a]!;
    const offB = this.#offsets[b]!;
    const lenA = this.#lengths[a]!;
    const lenB = this.#lengths[b]!;
    const n = Math.min(lenA, lenB);
    for (let k = 0; k < n; k++) {
      const d = arena[offA + k]! - arena[offB + k]!;
      if (d !== 0) return d;
    }
    return lenA - lenB;
  }

  #wordOf(e: number): string {
    const off = this.#offsets[e]!;
    return Buffer.from(this.#arena.buffer, this.#arena.byteOffset + off, this.#lengths[e]!).toString('latin1');
  }
}

function grow(buf: Uint8Array, minLength: number): Uint8Array {
  let length = buf.length * 2;
  while (length < minLength) length *= 2;
  const next = new Uint8Array(length);
  next.set(buf);
  return next;
}

function resize<T extends Uint32Array | Int32Array | Float64Array>(from: T, to: T): T {
  to.set(from);
  return to;
}
