// wordfreq: print the 10 most frequent ASCII words read from stdin.

import process from 'node:process';

const TOP_N = 10;

const CHAR_UPPER_A = 0x41;
const CHAR_UPPER_Z = 0x5a;
const CHAR_LOWER_A = 0x61;
const CHAR_LOWER_Z = 0x7a;
const CASE_BIT = 0x20;

type Entry = readonly [word: string, count: number];

/**
 * Streaming word counter. Accepts raw byte chunks; a word that straddles a
 * chunk boundary is carried over until the next separator (or end of input).
 */
class WordCounter {
  readonly #counts = new Map<string, number>();
  #pending = '';

  /** Consumes a chunk. The chunk is lowercased in place. */
  push(chunk: Buffer): void {
    const len = chunk.length;
    let start = -1;
    for (let i = 0; i < len; i++) {
      const b = chunk[i]!;
      if (b >= CHAR_LOWER_A && b <= CHAR_LOWER_Z) {
        if (start < 0) start = i;
      } else if (b >= CHAR_UPPER_A && b <= CHAR_UPPER_Z) {
        chunk[i] = b | CASE_BIT;
        if (start < 0) start = i;
      } else if (start >= 0) {
        this.#emit(chunk.latin1Slice(start, i), start === 0);
        start = -1;
      } else {
        this.#flushPending();
      }
    }
    if (start >= 0) {
      // Word runs to the end of the chunk; it may continue in the next one.
      this.#pending += chunk.latin1Slice(start, len);
    }
  }

  /** Flushes any carried-over word and returns the final counts. */
  finish(): ReadonlyMap<string, number> {
    this.#flushPending();
    return this.#counts;
  }

  #emit(word: string, continuesPending: boolean): void {
    if (continuesPending && this.#pending) {
      word = this.#pending + word;
      this.#pending = '';
    }
    this.#add(word);
  }

  #flushPending(): void {
    if (this.#pending) {
      this.#add(this.#pending);
      this.#pending = '';
    }
  }

  #add(word: string): void {
    this.#counts.set(word, (this.#counts.get(word) ?? 0) + 1);
  }
}

/** Orders by count descending, then word ascending (byte order). */
function compareEntries(a: Entry, b: Entry): number {
  if (a[1] !== b[1]) return b[1] - a[1];
  return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
}

/** Selects the `n` highest-ranked entries in one pass, without a full sort. */
function topWords(counts: ReadonlyMap<string, number>, n: number): Entry[] {
  const top: Entry[] = [];
  for (const entry of counts) {
    if (top.length === n && compareEntries(entry, top[n - 1]!) >= 0) continue;
    let i = top.length < n ? top.length : n - 1;
    while (i > 0 && compareEntries(entry, top[i - 1]!) < 0) {
      top[i] = top[i - 1]!;
      i--;
    }
    top[i] = entry;
  }
  return top;
}

async function main(): Promise<void> {
  const counter = new WordCounter();
  for await (const chunk of process.stdin as AsyncIterable<Buffer>) counter.push(chunk);
  const output = topWords(counter.finish(), TOP_N)
    .map(([word, count]) => `${count} ${word}\n`)
    .join('');
  process.stdout.write(output);
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.message : String(err);
  process.stderr.write(`wordfreq: ${message}\n`);
  process.exitCode = 1;
});
