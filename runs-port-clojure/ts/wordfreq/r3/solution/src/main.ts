/** Entry point: prints the 10 most frequent ASCII words read from standard input. */
import { readSync, writeSync } from 'node:fs';
import { countWords, topWords } from './wordfreq.ts';

const TOP_N = 10;
const CHUNK_SIZE = 1 << 20;

function readAllStdin(): Buffer {
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

function main(): void {
  const top = topWords(countWords(readAllStdin()), TOP_N);
  const output = top.map(({ word, count }) => `${count} ${word}\n`).join('');
  if (output.length > 0) writeAll(1, Buffer.from(output, 'latin1'));
}

main();
