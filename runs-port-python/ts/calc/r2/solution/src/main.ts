import { readFileSync, writeSync } from 'node:fs';
import { run } from './calc.ts';

function writeAll(fd: number, text: string): void {
  const buf = Buffer.from(text, 'latin1');
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(fd, buf, offset);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'EAGAIN') throw err;
    }
  }
}

function main(): number {
  // latin1 maps each byte to one code unit, so non-ASCII bytes stay invalid characters.
  const input = readFileSync(0).toString('latin1');
  const out = Array.from(run(input.split('\n'))).join('\n');
  if (out.length > 0) writeAll(1, out + '\n');
  return 0;
}

process.exitCode = main();
