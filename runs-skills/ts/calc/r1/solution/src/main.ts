import { readFileSync } from 'node:fs';
import { processLine } from './calc.ts';

function main(): void {
  const input = readFileSync(0, 'latin1');
  const out: string[] = [];
  for (const line of input.split('\n')) {
    const result = processLine(line);
    if (result !== null) out.push(result, '\n');
  }
  process.stdout.write(out.join(''));
}

main();
