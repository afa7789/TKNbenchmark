'use strict';

const { readFileSync, writeSync } = require('node:fs');
const { processLine } = require('./calc.js');

function main() {
  const input = readFileSync(0, 'latin1');
  const lines = input.split('\n');
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();

  const out = [];
  for (const line of lines) {
    const result = processLine(line);
    if (result !== null) out.push(result);
  }
  if (out.length === 0) return;

  const buf = Buffer.from(out.join('\n') + '\n');
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
