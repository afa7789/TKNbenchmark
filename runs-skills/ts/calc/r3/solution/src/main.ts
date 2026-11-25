import { readFileSync, writeSync } from 'node:fs';
import { evaluateLine } from './calc.ts';

function main(): void {
  const input = readFileSync(0, 'latin1');
  const lines = input.split('\n');
  if (lines.at(-1) === '') lines.pop();

  const out: string[] = [];
  for (const line of lines) {
    const result = evaluateLine(line);
    if (result !== undefined) out.push(result);
  }
  if (out.length > 0) writeAll(out.join('\n') + '\n');
}

function writeAll(text: string): void {
  const buf = Buffer.from(text, 'latin1');
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(1, buf, offset);
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== 'EAGAIN') throw e;
    }
  }
}

main();
