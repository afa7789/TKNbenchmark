/**
 * Print the 10 most frequent ASCII words read from standard input.
 *
 * A word is a maximal run of ASCII letters; every other byte is a separator.
 * Words are folded to lowercase and reported as `<count> <word>`, ordered by
 * count descending, then word ascending (byte order).
 */

import { readFileSync, writeSync } from 'node:fs';

export const TOP_N = 10;

export interface WordCount {
  readonly word: string;
  readonly count: number;
}

const CASE_BIT = 0x20;

/** Lookup table: lowercase code for ASCII letters, 0 for separators. */
const LOWER: Uint8Array = (() => {
  const table = new Uint8Array(256);
  for (let b = 0x41; b <= 0x5a; b++) {
    table[b] = b | CASE_BIT;
    table[b | CASE_BIT] = b | CASE_BIT;
  }
  return table;
})();

/** Count lowercase words in `data`. The buffer is lowercased in place. */
export function countWords(data: Buffer): Map<string, number> {
  const counts = new Map<string, number>();
  const len = data.length;
  let start = -1;
  for (let i = 0; i < len; i++) {
    const lower = LOWER[data[i]];
    if (lower !== 0) {
      data[i] = lower;
      if (start < 0) start = i;
    } else if (start >= 0) {
      const word = data.toString('latin1', start, i);
      counts.set(word, (counts.get(word) ?? 0) + 1);
      start = -1;
    }
  }
  if (start >= 0) {
    const word = data.toString('latin1', start, len);
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  return counts;
}

/** Ranking order: count descending, then word ascending (ASCII, so byte order). */
function compare(a: WordCount, b: WordCount): number {
  if (a.count !== b.count) return b.count - a.count;
  return a.word < b.word ? -1 : a.word > b.word ? 1 : 0;
}

/** Return up to `n` entries by count descending, then word ascending. */
export function topWords(counts: Map<string, number>, n: number = TOP_N): WordCount[] {
  // Keep a small sorted list of the best `n` seen so far; O(distinct * n) worst case.
  const top: WordCount[] = [];
  if (n <= 0) return top;
  for (const [word, count] of counts) {
    const entry: WordCount = { word, count };
    if (top.length === n && compare(entry, top[n - 1]) >= 0) continue;
    let pos = top.length;
    while (pos > 0 && compare(entry, top[pos - 1]) < 0) pos--;
    top.splice(pos, 0, entry);
    if (top.length > n) top.pop();
  }
  return top;
}

function main(): number {
  const data = readFileSync(0);
  const out = topWords(countWords(data))
    .map(({ word, count }) => `${count} ${word}\n`)
    .join('');
  if (out.length > 0) writeSync(1, out);
  return 0;
}

process.exitCode = main();
