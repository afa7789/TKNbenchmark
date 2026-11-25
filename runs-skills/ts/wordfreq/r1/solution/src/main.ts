import { readSync } from 'node:fs';
import { WordCounter } from './wordcount.ts';

const TOP_N = 10;
const CHUNK_SIZE = 1 << 20;

/** Reads all of stdin into a single buffer so words never straddle chunk boundaries. */
function readStdin(): Buffer {
  const chunks: Buffer[] = [];
  let total = 0;
  for (;;) {
    const chunk = Buffer.allocUnsafe(CHUNK_SIZE);
    let n: number;
    try {
      n = readSync(0, chunk, 0, CHUNK_SIZE, null);
    } catch (err) {
      if (Error.isError(err) && 'code' in err) {
        if (err.code === 'EAGAIN') continue;
        if (err.code === 'EOF') break;
      }
      throw err;
    }
    if (n === 0) break;
    chunks.push(n === CHUNK_SIZE ? chunk : chunk.subarray(0, n));
    total += n;
  }
  return Buffer.concat(chunks, total);
}

function main(): void {
  const counter = new WordCounter();
  counter.add(readStdin());
  const lines = counter.top(TOP_N).map(({ count, word }) => `${count} ${word}\n`);
  process.stdout.write(lines.join(''));
}

main();
