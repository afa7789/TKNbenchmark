/**
 * Word-frequency counting over raw bytes.
 *
 * A word is a maximal run of ASCII letters, folded to lowercase. Every other
 * byte is a separator. Words are stored in a byte arena and indexed by an
 * open-addressing hash table, so no per-word strings are allocated while
 * counting; this keeps throughput high on large inputs.
 */

/** Maps each byte to its lowercase ASCII letter, or 0 if it is a separator. */
const LOWER: Uint8Array = (() => {
  const table = new Uint8Array(256);
  for (let c = 0x61; c <= 0x7a; c++) {
    table[c] = c;
    table[c - 0x20] = c;
  }
  return table;
})();

const FNV_OFFSET = 0x811c9dc5;
const FNV_PRIME = 0x01000193;
const EMPTY = -1;

export interface WordCount {
  readonly word: string;
  readonly count: number;
}

export class WordCounter {
  /** Concatenated bytes of all distinct words, followed by the word in progress. */
  #arena = new Uint8Array(1 << 16);
  #arenaUsed = 0;

  /** Per-entry columns. */
  #offsets = new Int32Array(1 << 10);
  #lengths = new Int32Array(1 << 10);
  #hashes = new Int32Array(1 << 10);
  #counts = new Float64Array(1 << 10);
  #size = 0;

  /** Hash slots holding entry indices, or EMPTY. Capacity is a power of two. */
  #slots = new Int32Array(1 << 11).fill(EMPTY);

  /** State of a word that may continue into the next chunk. */
  #inWord = false;
  #wordStart = 0;
  #wordHash = FNV_OFFSET;

  /** Number of distinct words seen so far (excluding any unfinished word). */
  get distinct(): number {
    return this.#size;
  }

  /** Feeds the next chunk of input. Words may span chunk boundaries. */
  write(chunk: Uint8Array): void {
    let inWord = this.#inWord;
    let hash = this.#wordHash;
    let arena = this.#arena;
    let used = this.#arenaUsed;

    for (let i = 0; i < chunk.length; i++) {
      const c = LOWER[chunk[i]!]!;
      if (c !== 0) {
        if (!inWord) {
          inWord = true;
          hash = FNV_OFFSET;
          this.#wordStart = used;
        }
        if (used === arena.length) {
          this.#arenaUsed = used;
          arena = this.#growArena(used + 1);
        }
        arena[used++] = c;
        hash = Math.imul(hash ^ c, FNV_PRIME);
      } else if (inWord) {
        inWord = false;
        this.#arenaUsed = used;
        this.#commit(hash);
        arena = this.#arena;
        used = this.#arenaUsed;
      }
    }

    this.#inWord = inWord;
    this.#wordHash = hash;
    this.#arenaUsed = used;
  }

  /** Signals end of input, completing any word in progress. */
  end(): void {
    if (this.#inWord) {
      this.#inWord = false;
      this.#commit(this.#wordHash);
    }
  }

  /**
   * Returns up to `limit` words ordered by count descending, then by word
   * ascending in byte order.
   */
  top(limit: number): WordCount[] {
    if (limit <= 0) return [];
    const best: number[] = [];
    for (let e = 0; e < this.#size; e++) {
      if (best.length === limit && !this.#before(e, best[limit - 1]!)) continue;
      let pos = best.length < limit ? best.length : limit - 1;
      while (pos > 0 && this.#before(e, best[pos - 1]!)) {
        best[pos] = best[pos - 1]!;
        pos--;
      }
      best[pos] = e;
    }
    return best.map((e) => ({ word: this.#wordOf(e), count: this.#counts[e]! }));
  }

  /** Inserts or increments the word occupying arena[#wordStart, #arenaUsed). */
  #commit(rawHash: number): void {
    const start = this.#wordStart;
    const length = this.#arenaUsed - start;
    const hash = rawHash | 0;
    const mask = this.#slots.length - 1;
    let slot = hash & mask;

    for (;;) {
      const e = this.#slots[slot]!;
      if (e === EMPTY) break;
      if (this.#hashes[e] === hash && this.#lengths[e] === length && this.#equals(this.#offsets[e]!, start, length)) {
        this.#counts[e]!++;
        this.#arenaUsed = start; // discard the duplicate bytes
        return;
      }
      slot = (slot + 1) & mask;
    }

    const e = this.#size++;
    if (e === this.#offsets.length) this.#growEntries();
    this.#offsets[e] = start;
    this.#lengths[e] = length;
    this.#hashes[e] = hash;
    this.#counts[e] = 1;
    this.#slots[slot] = e;
    if (this.#size * 2 > this.#slots.length) this.#rehash();
  }

  #equals(a: number, b: number, length: number): boolean {
    const arena = this.#arena;
    for (let i = 0; i < length; i++) {
      if (arena[a + i] !== arena[b + i]) return false;
    }
    return true;
  }

  /** True if entry `a` sorts before entry `b` in output order. */
  #before(a: number, b: number): boolean {
    const ca = this.#counts[a]!;
    const cb = this.#counts[b]!;
    if (ca !== cb) return ca > cb;
    return this.#compareWords(a, b) < 0;
  }

  #compareWords(a: number, b: number): number {
    const arena = this.#arena;
    const oa = this.#offsets[a]!;
    const ob = this.#offsets[b]!;
    const la = this.#lengths[a]!;
    const lb = this.#lengths[b]!;
    const n = Math.min(la, lb);
    for (let i = 0; i < n; i++) {
      const d = arena[oa + i]! - arena[ob + i]!;
      if (d !== 0) return d;
    }
    return la - lb;
  }

  #wordOf(e: number): string {
    const start = this.#offsets[e]!;
    return Buffer.from(this.#arena.buffer, this.#arena.byteOffset + start, this.#lengths[e]!).toString('latin1');
  }

  #growArena(minCapacity: number): Uint8Array {
    let capacity = this.#arena.length * 2;
    while (capacity < minCapacity) capacity *= 2;
    const next = new Uint8Array(capacity);
    next.set(this.#arena.subarray(0, this.#arenaUsed));
    this.#arena = next;
    return next;
  }

  #growEntries(): void {
    const capacity = this.#offsets.length * 2;
    const grow = <T extends Int32Array | Float64Array>(old: T, make: (n: number) => T): T => {
      const next = make(capacity);
      next.set(old);
      return next;
    };
    this.#offsets = grow(this.#offsets, (n) => new Int32Array(n));
    this.#lengths = grow(this.#lengths, (n) => new Int32Array(n));
    this.#hashes = grow(this.#hashes, (n) => new Int32Array(n));
    this.#counts = grow(this.#counts, (n) => new Float64Array(n));
  }

  #rehash(): void {
    const slots = new Int32Array(this.#slots.length * 2).fill(EMPTY);
    const mask = slots.length - 1;
    for (let e = 0; e < this.#size; e++) {
      let slot = this.#hashes[e]! & mask;
      while (slots[slot] !== EMPTY) slot = (slot + 1) & mask;
      slots[slot] = e;
    }
    this.#slots = slots;
  }
}

/** Formats results as `<count> <word>` lines, each terminated by a newline. */
export function formatCounts(counts: readonly WordCount[]): string {
  return counts.map(({ count, word }) => `${count} ${word}\n`).join('');
}
