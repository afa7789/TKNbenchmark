// wordfreq: print the 10 most frequent ASCII-letter words read from stdin.

const TOP_N = 10;

type Counts = Map<string, number>;

const isAsciiLetter = (c: number): boolean => (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);

/** Tokenizes a byte stream into lowercase words, tolerating words split across chunks. */
class WordCounter {
  readonly counts: Counts = new Map();
  #pending: Buffer = Buffer.alloc(0);

  feed(chunk: Buffer): void {
    const data = this.#pending.length > 0 ? Buffer.concat([this.#pending, chunk]) : chunk;
    const len = data.length;
    let start = -1;
    for (let i = 0; i < len; i++) {
      const c = data[i];
      if (isAsciiLetter(c)) {
        if (start < 0) start = i;
      } else if (start >= 0) {
        this.#add(data, start, i);
        start = -1;
      }
    }
    // A trailing word may continue in the next chunk; copy it so the chunk can be released.
    this.#pending = start >= 0 ? Buffer.from(data.subarray(start)) : Buffer.alloc(0);
  }

  finish(): void {
    if (this.#pending.length > 0) this.#add(this.#pending, 0, this.#pending.length);
    this.#pending = Buffer.alloc(0);
  }

  #add(data: Buffer, start: number, end: number): void {
    const word = data.toString('latin1', start, end).toLowerCase();
    this.counts.set(word, (this.counts.get(word) ?? 0) + 1);
  }
}

/** Highest counts first; ties broken by word in ascending byte order. */
function byRank(a: [string, number], b: [string, number]): number {
  if (a[1] !== b[1]) return b[1] - a[1];
  return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
}

/** Selects the top `n` entries without sorting the whole map. */
function topWords(counts: Counts, n: number): Array<[string, number]> {
  const top: Array<[string, number]> = [];
  for (const entry of counts) {
    if (top.length === n && byRank(entry, top[n - 1]) >= 0) continue;
    let i = top.length < n ? top.length : n - 1;
    while (i > 0 && byRank(entry, top[i - 1]) < 0) {
      if (i < n) top[i] = top[i - 1];
      i--;
    }
    top[i] = entry;
  }
  return top;
}

async function main(): Promise<void> {
  const counter = new WordCounter();
  for await (const chunk of process.stdin) counter.feed(chunk as Buffer);
  counter.finish();

  const out = topWords(counter.counts, TOP_N)
    .map(([word, count]) => `${count} ${word}\n`)
    .join('');
  process.stdout.write(out);
}

await main();
