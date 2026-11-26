/**
 * Entry point: reads expressions from stdin, one per line, and prints each
 * result (or "error") to stdout. Lines are split on '\n' only; a carriage
 * return stays part of its line and is therefore a syntax error.
 */
import { readFileSync, writeSync } from 'node:fs';
import { evalLine } from './calc.ts';

const FLUSH_THRESHOLD = 1 << 16;

function writeAll(fd: number, text: string): void {
  const buf = Buffer.from(text, 'latin1');
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(fd, buf, offset);
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'EAGAIN') continue;
      throw e;
    }
  }
}

function main(): void {
  const input = readFileSync(0).toString('latin1');
  const lines = input.split('\n');
  // A trailing newline does not start another line.
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();

  let out: string[] = [];
  let pending = 0;
  for (const line of lines) {
    const result = evalLine(line);
    if (result === null) continue;
    out.push(result);
    pending += result.length + 1;
    if (pending >= FLUSH_THRESHOLD) {
      writeAll(1, out.join('\n') + '\n');
      out = [];
      pending = 0;
    }
  }
  if (out.length > 0) writeAll(1, out.join('\n') + '\n');
}

main();
