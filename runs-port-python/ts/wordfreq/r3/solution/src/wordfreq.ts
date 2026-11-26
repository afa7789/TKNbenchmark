/**
 * Print the 10 most frequent ASCII words read from standard input.
 *
 * A word is a maximal run of ASCII letters; every other byte is a separator.
 * Words are folded to lowercase and reported as `<count> <word>`, ordered by
 * count descending, then word ascending (byte order).
 */

const TOP_N = 10;
const SEPARATOR = 0x20;

/** Maps ASCII letters to lowercase and every other byte to a space. */
const FOLD_TABLE: Uint8Array = (() => {
  const table = new Uint8Array(256).fill(SEPARATOR);
  for (let b = 0x61; b <= 0x7a; b++) {
    table[b] = b;
    table[b - 0x20] = b;
  }
  return table;
})();

type Entry = readonly [word: string, count: number];

/** Accumulates word counts from a byte stream delivered in arbitrary chunks. */
export class WordCounter {
  readonly counts = new Map<string, number>();
  /** Lowercased prefix of a word that was cut off at the end of the previous chunk. */
  #carry = "";

  /** Counts the words in `chunk`. The chunk is folded in place. */
  update(chunk: Uint8Array): void {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength);
    const len = bytes.length;
    for (let i = 0; i < len; i++) bytes[i] = FOLD_TABLE[bytes[i]];

    let i = 0;
    if (this.#carry) {
      while (i < len && bytes[i] !== SEPARATOR) i++;
      const joined = this.#carry + bytes.toString("latin1", 0, i);
      if (i === len) {
        this.#carry = joined;
        return;
      }
      this.#carry = "";
      this.#add(joined);
    }

    while (i < len) {
      while (i < len && bytes[i] === SEPARATOR) i++;
      if (i === len) break;
      const start = i;
      while (i < len && bytes[i] !== SEPARATOR) i++;
      if (i === len) {
        this.#carry = bytes.toString("latin1", start, len);
        break;
      }
      this.#add(bytes.toString("latin1", start, i));
    }
  }

  /** Flushes any word left pending at end of input. */
  finish(): void {
    if (this.#carry) {
      this.#add(this.#carry);
      this.#carry = "";
    }
  }

  #add(word: string): void {
    this.counts.set(word, (this.counts.get(word) ?? 0) + 1);
  }
}

/** Orders entries by count descending, then word ascending. */
function compareEntries(a: Entry, b: Entry): number {
  if (a[1] !== b[1]) return b[1] - a[1];
  // Words are lowercase ASCII, so UTF-16 code unit order equals byte order.
  return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
}

/** Returns the `n` most frequent words without sorting the whole table. */
export function topWords(counts: ReadonlyMap<string, number>, n: number = TOP_N): Entry[] {
  const best: Entry[] = [];
  for (const entry of counts) {
    if (best.length === n && compareEntries(entry, best[n - 1]) >= 0) continue;
    let pos = best.length === n ? n - 1 : best.length;
    while (pos > 0 && compareEntries(entry, best[pos - 1]) < 0) {
      best[pos] = best[pos - 1];
      pos--;
    }
    best[pos] = entry;
  }
  return best;
}

async function main(): Promise<void> {
  const counter = new WordCounter();
  for await (const chunk of process.stdin) counter.update(chunk as Buffer);
  counter.finish();
  const out = topWords(counter.counts)
    .map(([word, count]) => `${count} ${word}\n`)
    .join("");
  if (out) process.stdout.write(out);
}

await main();
