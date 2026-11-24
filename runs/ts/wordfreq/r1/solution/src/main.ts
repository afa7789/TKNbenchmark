/**
 * wordfreq: read stdin, print the 10 most frequent ASCII-letter words.
 */

const TOP_N = 10;

const LOWER_A = 0x61;
const LOWER_Z = 0x7a;
const CASE_BIT = 0x20;

/** Returns the lowercase ASCII letter code for `byte`, or -1 if it is not a letter. */
function foldLetter(byte: number): number {
  const lower = byte | CASE_BIT;
  return lower >= LOWER_A && lower <= LOWER_Z ? lower : -1;
}

/** Incrementally tokenizes byte chunks into lowercase words and counts them. */
class WordCounter {
  readonly counts = new Map<string, number>();
  /** Word fragment carried over from the end of the previous chunk. */
  private pending = "";

  feed(chunk: Buffer): void {
    const len = chunk.length;
    let start = -1;
    for (let i = 0; i < len; i++) {
      const lower = foldLetter(chunk[i]);
      if (lower < 0) {
        if (start >= 0) {
          this.add(chunk, start, i);
          start = -1;
        } else if (this.pending !== "") {
          this.flushPending();
        }
      } else {
        chunk[i] = lower;
        if (start < 0) start = i;
      }
    }
    if (start >= 0) {
      this.pending += chunk.latin1Slice(start, len);
    }
  }

  finish(): Map<string, number> {
    if (this.pending !== "") this.flushPending();
    return this.counts;
  }

  private add(chunk: Buffer, start: number, end: number): void {
    let word = chunk.latin1Slice(start, end);
    if (this.pending !== "") {
      word = this.pending + word;
      this.pending = "";
    }
    this.increment(word);
  }

  private flushPending(): void {
    this.increment(this.pending);
    this.pending = "";
  }

  private increment(word: string): void {
    this.counts.set(word, (this.counts.get(word) ?? 0) + 1);
  }
}

/** Byte-order comparison; words are pure ASCII, so code-unit order equals byte order. */
function compareEntries(a: [string, number], b: [string, number]): number {
  if (a[1] !== b[1]) return b[1] - a[1];
  return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
}

/** Selects the top `n` entries without sorting the entire map. */
function topEntries(counts: Map<string, number>, n: number): [string, number][] {
  const top: [string, number][] = [];
  for (const entry of counts) {
    if (top.length === n && compareEntries(entry, top[n - 1]) >= 0) continue;
    let pos = top.length < n ? top.length : n - 1;
    top[pos] = entry;
    while (pos > 0 && compareEntries(top[pos], top[pos - 1]) < 0) {
      [top[pos], top[pos - 1]] = [top[pos - 1], top[pos]];
      pos--;
    }
  }
  return top;
}

async function main(): Promise<void> {
  const counter = new WordCounter();
  for await (const chunk of process.stdin) {
    counter.feed(chunk as Buffer);
  }
  const lines = topEntries(counter.finish(), TOP_N).map(([word, count]) => `${count} ${word}\n`);
  process.stdout.write(lines.join(""));
}

main().catch((err: unknown) => {
  process.stderr.write(`wordfreq: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exitCode = 1;
});
