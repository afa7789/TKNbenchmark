import { WordCounter } from "./word-counter.ts";

const LOWER_A = 0x61;
const LOWER_Z = 0x7a;
const CASE_BIT = 0x20;

/** Streams bytes into a {@link WordCounter}, carrying partial words across chunk boundaries. */
export class WordScanner {
  readonly counter = new WordCounter();
  #word = new Uint8Array(64);
  #wordLen = 0;
  #hash = 0;

  feed(chunk: Uint8Array): void {
    let word = this.#word;
    let wordLen = this.#wordLen;
    let hash = this.#hash;
    for (let i = 0; i < chunk.length; i++) {
      // Fold to lowercase: 'A'..'Z' | 0x20 -> 'a'..'z'; no other byte maps into 'a'..'z'.
      const lower = chunk[i] | CASE_BIT;
      if (lower >= LOWER_A && lower <= LOWER_Z) {
        if (wordLen === word.length) {
          const grown = new Uint8Array(word.length * 2);
          grown.set(word);
          word = grown;
        }
        word[wordLen++] = lower;
        hash = (Math.imul(hash, 31) + lower) | 0;
      } else if (wordLen > 0) {
        this.counter.add(word, 0, wordLen, hash);
        wordLen = 0;
        hash = 0;
      }
    }
    this.#word = word;
    this.#wordLen = wordLen;
    this.#hash = hash;
  }

  /** Flushes a trailing word, if any, and returns the counter. */
  finish(): WordCounter {
    if (this.#wordLen > 0) {
      this.counter.add(this.#word, 0, this.#wordLen, this.#hash);
      this.#wordLen = 0;
      this.#hash = 0;
    }
    return this.counter;
  }
}
