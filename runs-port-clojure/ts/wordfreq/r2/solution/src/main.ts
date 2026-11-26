/**
 * wordfreq: prints the 10 most frequent ASCII words read from standard input.
 *
 * A word is a maximal run of ASCII letters; every other byte is a separator.
 * Words are folded to lowercase and reported as `<count> <word>`, ordered by
 * count descending, then word ascending (byte order).
 */

const TOP_N = 10;

type WordCount = readonly [word: string, count: number];

async function readStdin(): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks);
}

/** Counts lowercase words in `data`. Folds letters to lowercase in place. */
export function countWords(data: Buffer): Map<string, number> {
  const counts = new Map<string, number>();
  const len = data.length;
  let start = -1;
  for (let i = 0; i < len; i++) {
    const b = data[i];
    // ASCII letter test: clear the case bit (0x20) and check for 'A'..'Z'.
    const upper = b & 0xdf;
    if (upper >= 0x41 && upper <= 0x5a) {
      data[i] = b | 0x20;
      if (start < 0) start = i;
    } else if (start >= 0) {
      addWord(counts, data.toString('latin1', start, i));
      start = -1;
    }
  }
  if (start >= 0) addWord(counts, data.toString('latin1', start, len));
  return counts;
}

function addWord(counts: Map<string, number>, word: string): void {
  counts.set(word, (counts.get(word) ?? 0) + 1);
}

/** Orders by count descending, then word ascending. */
function compareEntries(a: WordCount, b: WordCount): number {
  if (a[1] !== b[1]) return b[1] - a[1];
  return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
}

/** Returns up to `n` entries, most frequent first, without sorting the whole map. */
export function topWords(counts: Map<string, number>, n: number): WordCount[] {
  const top: WordCount[] = [];
  if (n <= 0) return top;
  for (const entry of counts) {
    if (top.length === n && compareEntries(entry, top[n - 1]) >= 0) continue;
    let pos = top.length === n ? n - 1 : top.length;
    while (pos > 0 && compareEntries(entry, top[pos - 1]) < 0) {
      top[pos] = top[pos - 1];
      pos--;
    }
    top[pos] = entry;
  }
  return top;
}

async function main(): Promise<void> {
  const counts = countWords(await readStdin());
  const output = topWords(counts, TOP_N)
    .map(([word, count]) => `${count} ${word}\n`)
    .join('');
  if (output.length > 0) process.stdout.write(output);
}

await main();
