import { readFileSync } from 'node:fs';
import { EvalError, evaluate, isBlank } from './evaluate.ts';

function evaluateLine(line: string): string {
  try {
    return evaluate(line).toString();
  } catch (err) {
    if (err instanceof EvalError) return 'error';
    throw err;
  }
}

function main(): void {
  const input = readFileSync(0, 'latin1');
  const lines = input.split('\n');
  if (lines.at(-1) === '') lines.pop();

  const out: string[] = [];
  for (const line of lines) {
    if (!isBlank(line)) out.push(evaluateLine(line));
  }
  if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
}

main();
