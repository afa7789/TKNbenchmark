#!/usr/bin/env node
import { readFileSync, writeSync } from 'node:fs';
import { evaluateLines } from './calc.js';

// latin1 keeps one char per byte, so any non-ASCII byte is simply a syntax error.
const input = readFileSync(0, 'latin1');
const out = evaluateLines(input);
if (out.length > 0) {
  const data = Buffer.from(out.join('\n') + '\n', 'latin1');
  for (let off = 0; off < data.length;) off += writeSync(1, data, off);
}
