// wordfreq: print the 10 most frequent ASCII words read from standard input.

const TOP_N = 10;

const UPPER_A = 0x41;
const UPPER_Z = 0x5a;
const LOWER_A = 0x61;
const LOWER_Z = 0x7a;
const CASE_OFFSET = LOWER_A - UPPER_A;

type WordCounts = Map<string, number>;
type Entry = readonly [word: string, count: number];

function addWord(counts: WordCounts, word: string): void {
  counts.set(word, (counts.get(word) ?? 0) + 1);
}

/**
 * Streams input chunks, accumulating lowercase words. Chunks are lowercased in
 * place; a word may straddle chunk boundaries, so the in-progress prefix is
 * carried across reads.
 */
async function countWords(input: AsyncIterable<Buffer>): Promise<WordCounts> {
  const counts: WordCounts = new Map();
  let carry = '';

  for await (const chunk of input) {
    let start = -1;
    for (let i = 0; i < chunk.length; i++) {
      const c = chunk[i];
      if (c >= LOWER_A && c <= LOWER_Z) {
        if (start < 0) start = i;
      } else if (c >= UPPER_A && c <= UPPER_Z) {
        chunk[i] = c + CASE_OFFSET;
        if (start < 0) start = i;
      } else if (start >= 0 || carry !== '') {
        const word = start >= 0 ? carry + chunk.toString('latin1', start, i) : carry;
        addWord(counts, word);
        carry = '';
        start = -1;
      }
    }
    if (start >= 0) carry += chunk.toString('latin1', start);
  }

  if (carry !== '') addWord(counts, carry);
  return counts;
}

function byRank(a: Entry, b: Entry): number {
  if (a[1] !== b[1]) return b[1] - a[1];
  if (a[0] === b[0]) return 0;
  return a[0] < b[0] ? -1 : 1;
}

/** Returns the `limit` highest-ranked entries using a bounded insertion pass. */
function topWords(counts: WordCounts, limit: number): Entry[] {
  const top: Entry[] = [];
  for (const entry of counts) {
    if (top.length === limit && byRank(entry, top[top.length - 1]) >= 0) continue;
    let pos = top.length;
    while (pos > 0 && byRank(entry, top[pos - 1]) < 0) pos--;
    top.splice(pos, 0, entry);
    if (top.length > limit) top.pop();
  }
  return top;
}

async function main(): Promise<void> {
  const counts = await countWords(process.stdin);
  const lines = topWords(counts, TOP_N).map(([word, count]) => `${count} ${word}\n`);
  process.stdout.write(lines.join(''));
}

await main();
