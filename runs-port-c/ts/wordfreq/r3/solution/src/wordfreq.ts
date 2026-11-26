/**
 * Word frequency counting: a word is a maximal run of ASCII letters,
 * folded to lowercase. Every other byte is a separator.
 */

export interface WordCount {
  readonly word: string;
  readonly count: number;
}

const LOWER_A = 0x61;
const CASE_BIT = 0x20;

function isAsciiLetter(byte: number): boolean {
  return ((byte | CASE_BIT) - LOWER_A) >>> 0 < 26;
}

/** Incrementally counts words across arbitrarily split byte chunks. */
export class WordCounter {
  readonly #counts = new Map<string, number>();
  /** Lowercased prefix of a word that ran up to the end of the previous chunk. */
  #pending = "";

  /** Feeds a chunk of input. The chunk's letters are lowercased in place. */
  feed(chunk: Uint8Array): void {
    const buf = Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength);
    const end = buf.length;
    let i = 0;
    while (i < end) {
      if (!isAsciiLetter(buf[i])) {
        i++;
        continue;
      }
      const start = i;
      do {
        buf[i] |= CASE_BIT;
        i++;
      } while (i < end && isAsciiLetter(buf[i]));

      if (start === 0 && this.#pending !== "") {
        this.#pending += buf.latin1Slice(start, i);
      } else {
        this.#flushPending();
        this.#pending = buf.latin1Slice(start, i);
      }
      if (i < end) this.#flushPending();
    }
    // A chunk ending on a separator terminates any pending word.
    if (end > 0 && !isAsciiLetter(buf[end - 1])) this.#flushPending();
  }

  /** Signals end of input, counting any word still in progress. */
  finish(): void {
    this.#flushPending();
  }

  /** Returns up to `n` words ordered by count descending, then word ascending. */
  top(n: number): WordCount[] {
    const best: WordCount[] = [];
    for (const [word, count] of this.#counts) {
      if (best.length === n && !ranksBefore(word, count, best[n - 1])) continue;
      let j = best.length < n ? best.length : n - 1;
      while (j > 0 && ranksBefore(word, count, best[j - 1])) {
        best[j] = best[j - 1];
        j--;
      }
      best[j] = { word, count };
    }
    return best;
  }

  #flushPending(): void {
    const word = this.#pending;
    if (word === "") return;
    this.#counts.set(word, (this.#counts.get(word) ?? 0) + 1);
    this.#pending = "";
  }
}

/** True if (word, count) should be listed before `other`. */
function ranksBefore(word: string, count: number, other: WordCount): boolean {
  if (count !== other.count) return count > other.count;
  // Words are lowercase ASCII, so UTF-16 comparison equals byte order.
  return word < other.word;
}
