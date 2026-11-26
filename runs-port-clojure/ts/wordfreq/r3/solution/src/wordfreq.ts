/** Core logic: counts ASCII words in a byte buffer and selects the most frequent ones. */

export interface WordCount {
  readonly word: string;
  readonly count: number;
}

const UPPER_A = 0x41;
const UPPER_Z = 0x5a;
const LOWER_A = 0x61;
const LOWER_Z = 0x7a;
const CASE_BIT = 0x20;

/**
 * Counts lowercase-folded words (maximal runs of ASCII letters) in `data`.
 * The buffer is lowercased in place to avoid per-word allocations.
 */
export function countWords(data: Buffer): Map<string, number> {
  const counts = new Map<string, number>();
  const len = data.length;
  let start = -1;

  for (let i = 0; i < len; i++) {
    const b = data[i];
    if (b >= LOWER_A && b <= LOWER_Z) {
      if (start < 0) start = i;
    } else if (b >= UPPER_A && b <= UPPER_Z) {
      data[i] = b | CASE_BIT;
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

/** Orders by count descending, then word ascending (byte order; words are ASCII). */
function compareEntries(a: WordCount, b: WordCount): number {
  if (a.count !== b.count) return b.count - a.count;
  return a.word < b.word ? -1 : a.word > b.word ? 1 : 0;
}

/** Returns up to `n` entries from `counts`, most frequent first. */
export function topWords(counts: ReadonlyMap<string, number>, n: number): WordCount[] {
  if (n <= 0) return [];
  // Bounded insertion into a small sorted array: O(entries * n) with tiny n.
  const top: WordCount[] = [];
  for (const [word, count] of counts) {
    const entry: WordCount = { word, count };
    if (top.length === n && compareEntries(entry, top[n - 1]) >= 0) continue;
    let pos = top.length < n ? top.length : n - 1;
    while (pos > 0 && compareEntries(entry, top[pos - 1]) < 0) {
      if (pos < top.length) top[pos] = top[pos - 1];
      else top.push(top[pos - 1]);
      pos--;
    }
    if (pos < top.length) top[pos] = entry;
    else top.push(entry);
  }
  return top;
}
