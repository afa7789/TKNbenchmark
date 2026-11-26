/**
 * wordfreq core: count case-folded ASCII-letter words and rank them.
 */

export interface WordCount {
  readonly word: string;
  readonly count: number;
}

const LOWER_A = 0x61;
const ALPHABET_SIZE = 26;
const CASE_BIT = 0x20;

/** True if the byte is an ASCII letter (A–Z or a–z). */
function isAlpha(byte: number): boolean {
  return ((byte | CASE_BIT) - LOWER_A) >>> 0 < ALPHABET_SIZE;
}

/**
 * Incremental word counter. Feed it raw byte chunks in order; words that span
 * chunk boundaries are stitched together.
 */
export class WordCounter {
  readonly #counts = new Map<string, number>();
  /** Lowercased prefix of a word that ran up to the end of the previous chunk. */
  #pending = "";

  /** Consumes a chunk of input. The chunk's bytes are not modified. */
  push(chunk: Uint8Array): void {
    const buf = Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength);
    const n = buf.length;
    let i = 0;

    while (i < n) {
      if (!isAlpha(buf[i])) {
        if (this.#pending !== "") this.#flushPending();
        i++;
        continue;
      }
      const start = i;
      while (i < n && isAlpha(buf[i])) i++;

      // Words are pure ASCII, so latin1 decoding maps bytes 1:1 to code units.
      const piece = buf.toString("latin1", start, i).toLowerCase();
      if (i < n) {
        this.#add(this.#pending === "" ? piece : this.#pending + piece);
        this.#pending = "";
      } else {
        this.#pending += piece;
      }
    }
  }

  /** Signals end of input, counting any word still in progress. */
  end(): void {
    if (this.#pending !== "") this.#flushPending();
  }

  /** Returns up to `limit` words, by count descending then word ascending. */
  top(limit: number): WordCount[] {
    const best: WordCount[] = [];
    for (const [word, count] of this.#counts) {
      const candidate = { word, count };
      if (best.length === limit && !ranksBefore(candidate, best[limit - 1])) continue;

      // Insertion into a small sorted array: O(entries * limit) overall.
      let j = best.length < limit ? best.length : limit - 1;
      while (j > 0 && ranksBefore(candidate, best[j - 1])) {
        best[j] = best[j - 1];
        j--;
      }
      best[j] = candidate;
    }
    return best;
  }

  #flushPending(): void {
    this.#add(this.#pending);
    this.#pending = "";
  }

  #add(word: string): void {
    this.#counts.set(word, (this.#counts.get(word) ?? 0) + 1);
  }
}

/** True if `a` should be ranked before `b`. */
function ranksBefore(a: WordCount, b: WordCount): boolean {
  if (a.count !== b.count) return a.count > b.count;
  // Words are ASCII, so UTF-16 code-unit order equals byte order.
  return a.word < b.word;
}
