// Word-frequency counting over raw bytes. A word is a maximal run of ASCII letters,
// folded to lowercase; every other byte is a separator.

const CASE_BIT = 0x20;
const LOWER_A = 0x61;
const LOWER_Z = 0x7a;

/**
 * Incremental counter: feed it byte chunks in order, then ask for the top words.
 * A word split across chunk boundaries is carried over and stitched together.
 */
export class WordCounter {
  #counts = new Map();
  #carry = '';

  /** @param {Buffer} chunk  Lowercased in place. */
  push(chunk) {
    const n = chunk.length;
    let start = 0;
    let inWord = this.#carry !== '';
    for (let i = 0; i < n; i++) {
      const folded = chunk[i] | CASE_BIT;
      if (folded >= LOWER_A && folded <= LOWER_Z) {
        chunk[i] = folded;
        if (!inWord) {
          start = i;
          inWord = true;
        }
      } else if (inWord) {
        this.#emit(chunk.latin1Slice(start, i));
        inWord = false;
      }
    }
    if (inWord) this.#carry += chunk.latin1Slice(start, n);
  }

  /** Flushes a word left pending at end of input. */
  end() {
    if (this.#carry !== '') this.#emit('');
  }

  #emit(tail) {
    let word = tail;
    if (this.#carry !== '') {
      word = this.#carry + tail;
      this.#carry = '';
    }
    this.#counts.set(word, (this.#counts.get(word) ?? 0) + 1);
  }

  /**
   * Single pass over the counts, keeping only the best `limit` entries in sorted order.
   * @param {number} limit
   * @returns {Array<[string, number]>} by count descending, then word ascending (byte order)
   */
  top(limit) {
    /** @type {Array<[string, number]>} */
    const best = [];
    if (limit <= 0) return best;
    for (const entry of this.#counts) {
      if (best.length === limit && !ranksBefore(entry, best[limit - 1])) continue;
      let i = best.length < limit ? best.length : limit - 1;
      while (i > 0 && ranksBefore(entry, best[i - 1])) {
        best[i] = best[i - 1];
        i--;
      }
      best[i] = entry;
    }
    return best;
  }
}

/** Ordering: higher count first, then lexicographically smaller word (ASCII, so byte order). */
function ranksBefore([wa, ca], [wb, cb]) {
  return ca !== cb ? ca > cb : wa < wb;
}
