import { readFileSync, writeSync } from 'node:fs';
import { evaluateLine } from './calc.js';

function main() {
  const input = readFileSync(0, 'latin1');
  const lines = input.split('\n');
  // A trailing newline terminates the last line rather than starting a new one.
  if (lines.at(-1) === '') lines.pop();

  const out = [];
  for (const line of lines) {
    const result = evaluateLine(line);
    if (result !== null) out.push(result);
  }
  if (out.length > 0) writeAll(out.join('\n') + '\n');
}

function writeAll(text) {
  const buf = Buffer.from(text);
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(1, buf, offset);
    } catch (err) {
      if (err.code !== 'EAGAIN') throw err;
    }
  }
}

main();
