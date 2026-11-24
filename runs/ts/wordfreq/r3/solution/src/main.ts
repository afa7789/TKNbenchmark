/**
 * wordfreq: print the 10 most frequent ASCII words read from standard input.
 *
 * A word is a maximal run of ASCII letters; every other byte is a separator.
 * Words are folded to lowercase and ranked by count descending, then by word
 * ascending (byte order).
 */

const TOP_N = 10;

const UPPER_A = 0x41;
const UPPER_Z = 0x5a;
const LOWER_A = 0x61;
const LOWER_Z = 0x7a;
const CASE_BIT = 0x20;

interface WordCount {
  readonly word: string;
  readonly count: number;
}

async function readStdin(): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks);
}

/**
 * Lowercases ASCII letters in place and replaces every non-letter byte with a
 * space, so the buffer can be decoded as latin1 and split on single bytes.
 * Returns the normalized text.
 */
function normalize(buf: Buffer): string {
  for (let i = 0; i < buf.length; i++) {
    const b = buf[i];
    if (b >= LOWER_A && b <= LOWER_Z) continue;
    if (b >= UPPER_A && b <= UPPER_Z) {
      buf[i] = b | CASE_BIT;
    } else {
      buf[i] = 0x20;
    }
  }
  return buf.toString('latin1');
}

function countWords(text: string): Map<string, number> {
  const counts = new Map<string, number>();
  const len = text.length;
  let i = 0;
  while (i < len) {
    while (i < len && text.charCodeAt(i) === 0x20) i++;
    if (i >= len) break;
    const start = i;
    while (i < len && text.charCodeAt(i) !== 0x20) i++;
    const word = text.slice(start, i);
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  return counts;
}

/** Byte-order comparison; words are pure ASCII so code-unit order matches. */
function ranksBefore(a: WordCount, b: WordCount): boolean {
  if (a.count !== b.count) return a.count > b.count;
  return a.word < b.word;
}

/** Selects the top `n` entries without sorting the whole map. */
function topWords(counts: Map<string, number>, n: number): WordCount[] {
  const top: WordCount[] = [];
  for (const [word, count] of counts) {
    const entry: WordCount = { word, count };
    if (top.length === n && !ranksBefore(entry, top[n - 1])) continue;
    let pos = top.length < n ? top.length : n - 1;
    while (pos > 0 && ranksBefore(entry, top[pos - 1])) {
      top[pos] = top[pos - 1];
      pos--;
    }
    top[pos] = entry;
  }
  return top;
}

async function main(): Promise<void> {
  const input = await readStdin();
  const top = topWords(countWords(normalize(input)), TOP_N);
  if (top.length === 0) return;
  process.stdout.write(top.map(({ count, word }) => `${count} ${word}\n`).join(''));
}

await main();
