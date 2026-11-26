import { readFileSync } from 'node:fs';
import { LRUCache } from './lru.ts';

/** Executes the command script and returns everything it prints. */
export function run(input: string): string {
  const lines = input.split('\n');
  const capacity = Number.parseInt(lines[0], 10);
  const cache = new LRUCache<string, string>(capacity);
  const out: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i];
    if (line.endsWith('\r')) line = line.slice(0, -1);
    if (line === '') continue;

    const [command, key, value] = line.split(' ');
    switch (command) {
      case 'SET':
        cache.set(key, value);
        break;
      case 'GET':
        out.push(cache.get(key) ?? 'NULL');
        break;
      case 'DEL':
        out.push(cache.delete(key) ? '1' : '0');
        break;
      case 'SIZE':
        out.push(String(cache.size));
        break;
      default:
        break; // ignore unknown commands
    }
  }

  return out.length > 0 ? out.join('\n') + '\n' : '';
}

function main(): void {
  const output = run(readFileSync(0, 'latin1'));
  if (output) process.stdout.write(output, 'latin1');
}

main();
