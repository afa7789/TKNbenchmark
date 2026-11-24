'use strict';

// wordfreq: read stdin, print the 10 most frequent ASCII-letter words.

const TOP_N = 10;

// Lookup table: 0 for separators, otherwise the lowercase ASCII byte.
const LOWER = new Uint8Array(256);
for (let c = 0x41; c <= 0x5a; c++) LOWER[c] = c | 0x20;
for (let c = 0x61; c <= 0x7a; c++) LOWER[c] = c;

/**
 * Incrementally counts words across arbitrarily split chunks of bytes.
 */
class WordCounter {
  constructor() {
    this.counts = new Map();
    this.pending = ''; // word fragment carried over from the previous chunk
  }

  add(word) {
    const { counts } = this;
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }

  /** @param {Buffer} chunk */
  feed(chunk) {
    const len = chunk.length;
    let start = -1;
    for (let i = 0; i < len; i++) {
      const lower = LOWER[chunk[i]];
      if (lower !== 0) {
        chunk[i] = lower;
        if (start < 0) start = i;
      } else if (start >= 0) {
        this.flush(chunk, start, i);
        start = -1;
      } else if (this.pending !== '') {
        this.add(this.pending);
        this.pending = '';
      }
    }
    if (start >= 0) this.pending += chunk.latin1Slice(start, len);
  }

  flush(chunk, start, end) {
    let word = chunk.latin1Slice(start, end);
    if (start === 0 && this.pending !== '') {
      word = this.pending + word;
      this.pending = '';
    }
    this.add(word);
  }

  finish() {
    if (this.pending !== '') {
      this.add(this.pending);
      this.pending = '';
    }
    return this.counts;
  }
}

/** True if entry a ranks before entry b (count desc, then word asc). */
function ranksBefore(aWord, aCount, bWord, bCount) {
  return aCount !== bCount ? aCount > bCount : aWord < bWord;
}

/** Returns the top `n` [word, count] pairs without sorting the whole map. */
function topEntries(counts, n) {
  const top = [];
  for (const [word, count] of counts) {
    if (top.length === n) {
      const [lastWord, lastCount] = top[n - 1];
      if (!ranksBefore(word, count, lastWord, lastCount)) continue;
      top.pop();
    }
    let i = top.length;
    while (i > 0 && ranksBefore(word, count, top[i - 1][0], top[i - 1][1])) i--;
    top.splice(i, 0, [word, count]);
  }
  return top;
}

function main() {
  const counter = new WordCounter();
  process.stdin.on('data', (chunk) => counter.feed(chunk));
  process.stdin.on('end', () => {
    const top = topEntries(counter.finish(), TOP_N);
    if (top.length > 0) {
      process.stdout.write(top.map(([word, count]) => `${count} ${word}\n`).join(''));
    }
  });
}

main();
