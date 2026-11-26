// wordfreq: print the 10 most frequent ASCII-letter words read from stdin.
import { stdin, stdout } from 'node:process';

const TOP_N = 10;

const UPPER_A = 0x41;
const UPPER_Z = 0x5a;
const LOWER_A = 0x61;
const LOWER_Z = 0x7a;
const CASE_BIT = 0x20;

async function readAll(stream: NodeJS.ReadableStream): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(typeof chunk === 'string' ? Buffer.from(chunk, 'latin1') : chunk);
  }
  return Buffer.concat(chunks);
}

const isUpper = (c: number): boolean => c >= UPPER_A && c <= UPPER_Z;
const isLower = (c: number): boolean => c >= LOWER_A && c <= LOWER_Z;

/** Lowercases `data` in place and counts each maximal run of ASCII letters. */
export function countWords(data: Buffer): Map<string, number> {
  const counts = new Map<string, number>();
  const size = data.length;
  let i = 0;
  while (i < size) {
    while (i < size) {
      const c = data[i];
      if (isLower(c) || isUpper(c)) break;
      i++;
    }
    const start = i;
    while (i < size) {
      const c = data[i];
      if (isUpper(c)) {
        data[i] = c | CASE_BIT;
      } else if (!isLower(c)) {
        break;
      }
      i++;
    }
    if (i > start) {
      const word = data.latin1Slice(start, i);
      counts.set(word, (counts.get(word) ?? 0) + 1);
    }
  }
  return counts;
}

type Entry = readonly [word: string, count: number];

const byRank = (a: Entry, b: Entry): number => {
  if (a[1] !== b[1]) return b[1] - a[1];
  return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
};

/** Returns the `n` highest-ranked entries without sorting the whole map. */
export function topEntries(counts: Map<string, number>, n: number): Entry[] {
  const top: Entry[] = [];
  for (const entry of counts) {
    if (top.length === n && byRank(entry, top[n - 1]) >= 0) continue;
    let pos = top.length < n ? top.push(entry) - 1 : n - 1;
    while (pos > 0 && byRank(entry, top[pos - 1]) < 0) {
      top[pos] = top[pos - 1];
      pos--;
    }
    top[pos] = entry;
  }
  return top;
}

async function main(): Promise<void> {
  const data = await readAll(stdin);
  const top = topEntries(countWords(data), TOP_N);
  const out = top.map(([word, count]) => `${count} ${word}\n`).join('');
  if (out.length > 0) stdout.write(out);
}

await main();
