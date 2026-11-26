import { readFileSync, writeSync } from 'node:fs';
import { processLine } from './calc.ts';

function writeAll(fd: number, buf: Buffer): void {
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(fd, buf, offset);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'EAGAIN') throw err;
    }
  }
}

function main(): void {
  const input = readFileSync(0, 'latin1');
  const lines = input.split('\n');
  if (lines.at(-1) === '') lines.pop();

  const out: string[] = [];
  for (const line of lines) {
    const result = processLine(line);
    if (result !== null) out.push(result);
  }
  if (out.length === 0) return;

  writeAll(1, Buffer.from(out.join('\n') + '\n'));
}

main();
