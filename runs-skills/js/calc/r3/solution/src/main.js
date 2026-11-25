#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { evaluateLine } from './calc.js';

const input = readFileSync(process.stdin.fd, 'latin1');
const lines = input.split('\n');
if (lines.at(-1) === '') lines.pop();

const out = [];
for (const line of lines) {
  const result = evaluateLine(line);
  if (result !== null) out.push(result);
}

if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
