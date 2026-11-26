/** calc: evaluate one 64-bit signed integer expression per input line. */
import { evaluate, isBlank } from './evaluator.ts';

const NEWLINE = 0x0a;
const FLUSH_THRESHOLD = 1 << 16;

function isBlankLine(line: Buffer): boolean {
  return line.every(isBlank);
}

/**
 * Read all of stdin via the stream API. A synchronous read on the stdin fd
 * fails with EAGAIN when stdin is a non-blocking pipe, so it is not used.
 */
async function readStdin(): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks);
}

async function main(): Promise<void> {
  const input = await readStdin();
  let out = '';

  let pos = 0;
  while (pos < input.length) {
    const nl = input.indexOf(NEWLINE, pos);
    const end = nl === -1 ? input.length : nl;
    const line = input.subarray(pos, end);
    pos = end + 1;

    if (isBlankLine(line)) continue;

    const value = evaluate(line);
    out += value === undefined ? 'error\n' : `${value}\n`;
    if (out.length >= FLUSH_THRESHOLD) {
      process.stdout.write(out);
      out = '';
    }
  }

  process.stdout.write(out);
}

await main();
