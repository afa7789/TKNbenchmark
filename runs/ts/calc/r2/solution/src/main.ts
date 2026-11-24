import { readFileSync, writeSync } from 'node:fs';
import { evaluateLine } from './calc.ts';

function writeAll(fd: number, data: string): void {
  const buf = Buffer.from(data, 'latin1');
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(fd, buf, offset);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'EAGAIN') continue;
      throw err;
    }
  }
}

function main(): void {
  const input = readFileSync(0, 'latin1');
  const lines = input.split('\n');
  if (lines.at(-1) === '') lines.pop();

  const out: string[] = [];
  for (const line of lines) {
    const result = evaluateLine(line);
    if (result !== null) out.push(result);
  }
  if (out.length > 0) writeAll(1, out.join('\n') + '\n');
}

main();
