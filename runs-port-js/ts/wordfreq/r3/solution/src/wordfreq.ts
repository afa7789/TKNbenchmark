// wordfreq: read stdin, print the 10 most frequent ASCII-letter words.

const TOP_N = 10;

/** Lookup table: 0 for separators, otherwise the lowercase ASCII byte. */
const LOWER: Uint8Array = (() => {
  const table = new Uint8Array(256);
  for (let c = 0x41; c <= 0x5a; c++) table[c] = c | 0x20;
  for (let c = 0x61; c <= 0x7a; c++) table[c] = c;
  return table;
})();

type Entry = readonly [word: string, count: number];

/** Incrementally counts words across arbitrarily split chunks of bytes. */
export class WordCounter {
  readonly #counts = new Map<string, number>();
  /** Word fragment carried over from the previous chunk. */
  #pending = '';

  /** Consumes a chunk of input. The chunk is lowercased in place. */
  feed(chunk: Uint8Array): void {
    const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength);
    const len = buf.length;
    let start = -1;
    for (let i = 0; i < len; i++) {
      const lower = LOWER[buf[i]];
      if (lower !== 0) {
        buf[i] = lower;
        if (start < 0) start = i;
      } else if (start >= 0) {
        this.#flush(buf, start, i);
        start = -1;
      } else if (this.#pending !== '') {
        this.#add(this.#pending);
        this.#pending = '';
      }
    }
    if (start >= 0) this.#pending += buf.toString('latin1', start, len);
  }

  /** Flushes any trailing word and returns the word counts. */
  finish(): ReadonlyMap<string, number> {
    if (this.#pending !== '') {
      this.#add(this.#pending);
      this.#pending = '';
    }
    return this.#counts;
  }

  #add(word: string): void {
    this.#counts.set(word, (this.#counts.get(word) ?? 0) + 1);
  }

  #flush(buf: Buffer, start: number, end: number): void {
    let word = buf.toString('latin1', start, end);
    if (start === 0 && this.#pending !== '') {
      word = this.#pending + word;
      this.#pending = '';
    }
    this.#add(word);
  }
}

/** True if entry a ranks before entry b (count desc, then word asc in byte order). */
function ranksBefore(aWord: string, aCount: number, bWord: string, bCount: number): boolean {
  return aCount !== bCount ? aCount > bCount : aWord < bWord;
}

/** Returns the top `n` entries without sorting the whole map. */
export function topEntries(counts: ReadonlyMap<string, number>, n: number): Entry[] {
  const top: Entry[] = [];
  if (n <= 0) return top;
  for (const [word, count] of counts) {
    if (top.length === n) {
      const [lastWord, lastCount] = top[n - 1];
      if (!ranksBefore(word, count, lastWord, lastCount)) continue;
      top.pop();
    }
    let i = top.length;
    while (i > 0 && ranksBefore(word, count, top[i - 1][0], top[i - 1][1])) i--;
    top.splice(i, 0, [word, count]);
  }
  return top;
}

async function main(): Promise<void> {
  const counter = new WordCounter();
  for await (const chunk of process.stdin) counter.feed(chunk as Buffer);
  const top = topEntries(counter.finish(), TOP_N);
  if (top.length > 0) {
    process.stdout.write(top.map(([word, count]) => `${count} ${word}\n`).join(''));
  }
}

await main();
