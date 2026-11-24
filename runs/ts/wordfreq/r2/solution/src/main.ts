import { readSync } from 'node:fs';

const TOP_N = 10;
const CHUNK_SIZE = 1 << 20;

/** Read all of standard input into a single Buffer. */
function readStdin(): Buffer {
  const chunks: Buffer[] = [];
  let total = 0;
  for (;;) {
    const chunk = Buffer.allocUnsafe(CHUNK_SIZE);
    let n: number;
    try {
      n = readSync(0, chunk, 0, CHUNK_SIZE, null);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'EAGAIN') continue;
      if (code === 'EOF') break;
      throw err;
    }
    if (n === 0) break;
    chunks.push(n === CHUNK_SIZE ? chunk : chunk.subarray(0, n));
    total += n;
  }
  return Buffer.concat(chunks, total);
}

/**
 * Count case-folded words (maximal runs of ASCII letters) in `data`.
 * The buffer is lowercased in place.
 */
export function countWords(data: Buffer): Map<string, number> {
  const counts = new Map<string, number>();
  const len = data.length;
  let i = 0;
  while (i < len) {
    // Skip separators.
    while (i < len && !isLetter(data[i])) i++;
    if (i >= len) break;
    const start = i;
    while (i < len) {
      const b = data[i];
      if (b >= 0x41 && b <= 0x5a) data[i] = b | 0x20;
      else if (!(b >= 0x61 && b <= 0x7a)) break;
      i++;
    }
    const word = data.latin1Slice(start, i);
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  return counts;
}

function isLetter(b: number): boolean {
  return (b >= 0x61 && b <= 0x7a) || (b >= 0x41 && b <= 0x5a);
}

/** Order by count descending, then word ascending (byte order; words are ASCII). */
function compareEntries(a: [string, number], b: [string, number]): number {
  if (a[1] !== b[1]) return b[1] - a[1];
  return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
}

/** Select the `n` best entries without sorting the whole map. */
export function topWords(counts: Map<string, number>, n: number): Array<[string, number]> {
  const top: Array<[string, number]> = [];
  for (const entry of counts) {
    if (top.length === n && compareEntries(entry, top[n - 1]) >= 0) continue;
    let pos = top.length < n ? top.length : n - 1;
    if (top.length < n) top.push(entry);
    while (pos > 0 && compareEntries(entry, top[pos - 1]) < 0) {
      top[pos] = top[pos - 1];
      pos--;
    }
    top[pos] = entry;
  }
  return top;
}

function main(): void {
  const counts = countWords(readStdin());
  const top = topWords(counts, TOP_N);
  if (top.length === 0) return;
  process.stdout.write(top.map(([word, count]) => `${count} ${word}\n`).join(''));
}

main();
