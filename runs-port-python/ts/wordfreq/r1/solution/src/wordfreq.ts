/**
 * Print the 10 most frequent ASCII words read from standard input.
 *
 * A word is a maximal run of ASCII letters; every other byte is a separator.
 * Words are folded to lowercase and ranked by count descending, then by word
 * ascending (byte order).
 */

const TOP_N = 10;

const SPACE = 0x20;
const LOWER_A = 0x61;
const LOWER_Z = 0x7a;

/** Maps every byte to its lowercase ASCII letter, or to a space for separators. */
const FOLD_TABLE: Uint8Array = (() => {
  const table = new Uint8Array(256).fill(SPACE);
  for (let b = LOWER_A; b <= LOWER_Z; b++) {
    table[b] = b;
    table[b & ~0x20] = b;
  }
  return table;
})();

export interface WordCount {
  readonly word: string;
  readonly count: number;
}

/** Counts the occurrences of each lowercase word in `data`. */
export function countWords(data: Uint8Array): Map<string, number> {
  const folded = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) folded[i] = FOLD_TABLE[data[i]!]!;

  // Every byte is now ASCII, so latin1 decoding maps bytes to chars one-to-one.
  const text = Buffer.from(folded.buffer, folded.byteOffset, folded.length).toString('latin1');
  const counts = new Map<string, number>();
  const length = folded.length;
  let i = 0;
  while (i < length) {
    while (i < length && folded[i] === SPACE) i++;
    if (i >= length) break;
    const start = i;
    while (i < length && folded[i] !== SPACE) i++;
    const word = text.slice(start, i);
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  return counts;
}

function compareEntries(a: WordCount, b: WordCount): number {
  if (a.count !== b.count) return b.count - a.count;
  // Words are pure ASCII, so UTF-16 code unit order equals byte order.
  return a.word < b.word ? -1 : a.word > b.word ? 1 : 0;
}

/** Returns up to `n` words ordered by count descending, then word ascending. */
export function topWords(data: Uint8Array, n: number = TOP_N): WordCount[] {
  const top: WordCount[] = [];
  for (const [word, count] of countWords(data)) {
    const entry: WordCount = { word, count };
    if (top.length === n && compareEntries(entry, top[n - 1]!) >= 0) continue;
    // Insert in sorted position, keeping at most n entries.
    let pos = top.length;
    while (pos > 0 && compareEntries(entry, top[pos - 1]!) < 0) pos--;
    top.splice(pos, 0, entry);
    if (top.length > n) top.pop();
  }
  return top;
}

async function readStdin(): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks);
}

async function main(): Promise<void> {
  const data = await readStdin();
  const output = topWords(data)
    .map(({ word, count }) => `${count} ${word}\n`)
    .join('');
  if (output.length > 0) process.stdout.write(output);
  process.exitCode = 0;
}

await main();
