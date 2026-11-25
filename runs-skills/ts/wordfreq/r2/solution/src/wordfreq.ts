/**
 * Word-frequency counting over raw bytes.
 *
 * A word is a maximal run of ASCII letters; everything else is a separator.
 * Words are folded to lowercase. Counting uses an open-addressing hash table
 * keyed by byte ranges of the input, so no per-word strings are allocated.
 */

export interface WordCount {
  readonly word: string;
  readonly count: number;
}

const FNV_OFFSET = 0x811c9dc5;
const FNV_PRIME = 0x01000193;
const INITIAL_CAPACITY = 1 << 12;

/** Lowercase ASCII letter for byte `b`, or -1 if `b` is not a letter. */
function foldLetter(b: number): number {
  const lower = b | 0x20;
  return lower >= 0x61 && lower <= 0x7a ? lower : -1;
}

class WordTable {
  #capacity = INITIAL_CAPACITY;
  #size = 0;
  #starts = new Int32Array(INITIAL_CAPACITY).fill(-1);
  #lengths = new Int32Array(INITIAL_CAPACITY);
  #hashes = new Uint32Array(INITIAL_CAPACITY);
  #counts = new Float64Array(INITIAL_CAPACITY);
  readonly #data: Uint8Array;

  constructor(data: Uint8Array) {
    this.#data = data;
  }

  add(start: number, length: number, hash: number): void {
    const data = this.#data;
    const mask = this.#capacity - 1;
    let slot = hash & mask;
    for (;;) {
      const s = this.#starts[slot]!;
      if (s === -1) break;
      if (this.#hashes[slot] === hash && this.#lengths[slot] === length && bytesEqual(data, s, start, length)) {
        this.#counts[slot]!++;
        return;
      }
      slot = (slot + 1) & mask;
    }
    this.#starts[slot] = start;
    this.#lengths[slot] = length;
    this.#hashes[slot] = hash;
    this.#counts[slot] = 1;
    if (++this.#size * 2 > this.#capacity) this.#grow();
  }

  #grow(): void {
    const oldStarts = this.#starts;
    const oldLengths = this.#lengths;
    const oldHashes = this.#hashes;
    const oldCounts = this.#counts;
    const capacity = this.#capacity * 2;
    const mask = capacity - 1;
    this.#capacity = capacity;
    this.#starts = new Int32Array(capacity).fill(-1);
    this.#lengths = new Int32Array(capacity);
    this.#hashes = new Uint32Array(capacity);
    this.#counts = new Float64Array(capacity);
    for (let i = 0; i < oldStarts.length; i++) {
      const s = oldStarts[i]!;
      if (s === -1) continue;
      const hash = oldHashes[i]!;
      let slot = hash & mask;
      while (this.#starts[slot] !== -1) slot = (slot + 1) & mask;
      this.#starts[slot] = s;
      this.#lengths[slot] = oldLengths[i]!;
      this.#hashes[slot] = hash;
      this.#counts[slot] = oldCounts[i]!;
    }
  }

  /** Yields [start, length, count] for every distinct word. */
  *entries(): Generator<[number, number, number]> {
    for (let i = 0; i < this.#capacity; i++) {
      const s = this.#starts[i]!;
      if (s !== -1) yield [s, this.#lengths[i]!, this.#counts[i]!];
    }
  }
}

function bytesEqual(data: Uint8Array, a: number, b: number, length: number): boolean {
  for (let i = 0; i < length; i++) {
    if (data[a + i] !== data[b + i]) return false;
  }
  return true;
}

function compareWordCounts(x: WordCount, y: WordCount): number {
  if (x.count !== y.count) return y.count - x.count;
  return x.word < y.word ? -1 : x.word > y.word ? 1 : 0;
}

/**
 * Returns the `limit` most frequent words in `data`, ordered by count
 * descending and then by word ascending. `data` is lowercased in place.
 */
export function topWords(data: Uint8Array, limit: number): WordCount[] {
  const table = new WordTable(data);
  const n = data.length;
  let start = -1;
  let hash = FNV_OFFSET;
  for (let i = 0; i < n; i++) {
    const c = foldLetter(data[i]!);
    if (c === -1) {
      if (start !== -1) {
        table.add(start, i - start, hash >>> 0);
        start = -1;
      }
      continue;
    }
    data[i] = c;
    if (start === -1) {
      start = i;
      hash = FNV_OFFSET;
    }
    hash = Math.imul(hash ^ c, FNV_PRIME);
  }
  if (start !== -1) table.add(start, n - start, hash >>> 0);

  // Keep a small sorted buffer of the best `limit` entries; decode words lazily.
  const decoder = new TextDecoder('latin1');
  const best: WordCount[] = [];
  for (const [s, length, count] of table.entries()) {
    const worst = best[best.length - 1];
    if (best.length >= limit && worst !== undefined && count < worst.count) continue;
    const candidate: WordCount = { word: decoder.decode(data.subarray(s, s + length)), count };
    if (best.length >= limit && worst !== undefined && compareWordCounts(candidate, worst) >= 0) continue;
    let pos = best.length;
    while (pos > 0 && compareWordCounts(candidate, best[pos - 1]!) < 0) pos--;
    best.splice(pos, 0, candidate);
    if (best.length > limit) best.pop();
  }
  return best;
}
