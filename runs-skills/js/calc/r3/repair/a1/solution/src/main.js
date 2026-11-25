#!/usr/bin/env node
import { evaluateLine } from './calc.js';

// Read stdin asynchronously: a synchronous read on a non-blocking pipe can
// fail with EAGAIN when input arrives in chunks.
async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('latin1');
}

const input = await readStdin();
const lines = input.split('\n');
if (lines.at(-1) === '') lines.pop();

const out = [];
for (const line of lines) {
  const result = evaluateLine(line);
  if (result !== null) out.push(result);
}

if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
