'use strict';

// wordfreq: print the 10 most frequent ASCII words read from stdin.

const TOP_N = 10;

const isUpper = (b) => b >= 0x41 && b <= 0x5a;
const isLower = (b) => b >= 0x61 && b <= 0x7a;

/**
 * Streaming word counter. Feeds raw byte chunks; words that straddle chunk
 * boundaries are carried over until the next separator (or end of input).
 */
class WordCounter {
  constructor() {
    this.counts = new Map();
    this.pending = '';
  }

  add(word) {
    this.counts.set(word, (this.counts.get(word) ?? 0) + 1);
  }

  push(chunk) {
    const len = chunk.length;
    let start = -1;
    for (let i = 0; i < len; i++) {
      const b = chunk[i];
      if (isLower(b)) {
        if (start < 0) start = i;
      } else if (isUpper(b)) {
        chunk[i] = b | 0x20;
        if (start < 0) start = i;
      } else if (start >= 0) {
        this.emit(chunk, start, i);
        start = -1;
      } else if (this.pending) {
        this.add(this.pending);
        this.pending = '';
      }
    }
    if (start >= 0) {
      this.pending += chunk.latin1Slice(start, len);
    }
  }

  emit(chunk, start, end) {
    let word = chunk.latin1Slice(start, end);
    if (this.pending && start === 0) {
      word = this.pending + word;
      this.pending = '';
    }
    this.add(word);
  }

  finish() {
    if (this.pending) {
      this.add(this.pending);
      this.pending = '';
    }
    return this.counts;
  }
}

function topWords(counts, n) {
  return [...counts]
    .sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .slice(0, n);
}

async function main() {
  const counter = new WordCounter();
  for await (const chunk of process.stdin) counter.push(chunk);
  const lines = topWords(counter.finish(), TOP_N).map(([w, c]) => `${c} ${w}\n`);
  process.stdout.write(lines.join(''));
}

main().catch((err) => {
  process.stderr.write(`wordfreq: ${err?.message ?? err}\n`);
  process.exitCode = 1;
});
