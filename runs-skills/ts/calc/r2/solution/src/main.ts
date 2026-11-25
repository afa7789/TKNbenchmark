import { readFileSync } from 'node:fs';
import { evaluate, isBlankLine } from './calc.ts';

function main(): void {
  const input = readFileSync(0, 'latin1');
  const lines = input.split('\n');
  // A trailing newline yields one final empty element, which is blank anyway.
  const out: string[] = [];
  for (const line of lines) {
    if (isBlankLine(line)) continue;
    out.push(evaluate(line)?.toString() ?? 'error');
  }
  if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
  process.exitCode = 0;
}

main();
