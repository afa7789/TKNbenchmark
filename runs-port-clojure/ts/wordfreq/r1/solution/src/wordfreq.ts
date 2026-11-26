/**
 * Prints the ten most frequent ASCII words read from standard input.
 *
 * A word is a maximal run of ASCII letters; every other byte is a separator.
 * Words are folded to lowercase and ranked by count descending, then by word
 * ascending (byte order).
 */
import { readSync, writeSync } from 'node:fs';

const TOP_N = 10;
const UPPER_A = 0x41;
const UPPER_Z = 0x5a;
const LOWER_A = 0x61;
const LOWER_Z = 0x7a;
const CASE_BIT = 0x20;

export interface WordCount {
  readonly word: string;
  readonly count: number;
}

/** Reads standard input to EOF, tolerating pipes, files and TTYs. */
export function readStdin(): Buffer {
  const chunks: Buffer[] = [];
  let total = 0;
  for (;;) {
    const chunk = Buffer.allocUnsafe(1 << 20);
    let n: number;
    try {
      n = readSync(0, chunk, 0, chunk.length, null);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'EAGAIN') continue;
      if (code === 'EOF') break;
      throw err;
    }
    if (n === 0) break;
    chunks.push(n === chunk.length ? chunk : chunk.subarray(0, n));
    total += n;
  }
  return Buffer.concat(chunks, total);
}

/**
 * Counts lowercased words in `buf`. The buffer is lowercased in place to avoid
 * copying each word before it is turned into a key.
 */
export function countWords(buf: Buffer): Map<string, number> {
  const counts = new Map<string, number>();
  const n = buf.length;
  let start = -1;
  for (let i = 0; i < n; i++) {
    const b = buf[i];
    if (b >= UPPER_A && b <= UPPER_Z) {
      buf[i] = b | CASE_BIT;
      if (start < 0) start = i;
    } else if (b >= LOWER_A && b <= LOWER_Z) {
      if (start < 0) start = i;
    } else if (start >= 0) {
      const word = buf.toString('latin1', start, i);
      counts.set(word, (counts.get(word) ?? 0) + 1);
      start = -1;
    }
  }
  if (start >= 0) {
    const word = buf.toString('latin1', start, n);
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  return counts;
}

/** Count descending, then word ascending. Words are ASCII, so `<` is byte order. */
function compareWordCounts(a: WordCount, b: WordCount): number {
  if (a.count !== b.count) return b.count - a.count;
  return a.word < b.word ? -1 : a.word > b.word ? 1 : 0;
}

/** Returns the `n` highest-ranked entries without sorting the whole map. */
export function topWords(counts: Map<string, number>, n: number): WordCount[] {
  const top: WordCount[] = [];
  if (n <= 0) return top;
  for (const [word, count] of counts) {
    const entry: WordCount = { word, count };
    if (top.length === n && compareWordCounts(entry, top[n - 1]) >= 0) continue;
    let pos = top.length === n ? n - 1 : top.length;
    while (pos > 0 && compareWordCounts(entry, top[pos - 1]) < 0) {
      top[pos] = top[pos - 1];
      pos--;
    }
    top[pos] = entry;
  }
  return top;
}

function writeAll(fd: number, data: Buffer): void {
  let offset = 0;
  while (offset < data.length) {
    try {
      offset += writeSync(fd, data, offset);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'EAGAIN') throw err;
    }
  }
}

export function main(): void {
  const top = topWords(countWords(readStdin()), TOP_N);
  const out = top.map(({ word, count }) => `${count} ${word}\n`).join('');
  if (out.length > 0) writeAll(1, Buffer.from(out, 'latin1'));
}

main();
