import { readFileSync } from 'node:fs';
import { LruCache } from './lru.ts';

/** Runs the command script in `input` and returns the output lines. */
export function run(input: string): string[] {
  const lines = input.split('\n');
  const capacity = Number.parseInt(lines[0] ?? '', 10);
  const cache = new LruCache<string, string>(capacity);
  const out: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i] ?? '';
    if (line.endsWith('\r')) line = line.slice(0, -1);
    if (line === '') continue;

    const firstSpace = line.indexOf(' ');
    const command = firstSpace < 0 ? line : line.slice(0, firstSpace);
    const rest = firstSpace < 0 ? '' : line.slice(firstSpace + 1);

    switch (command) {
      case 'SET': {
        const sep = rest.indexOf(' ');
        if (sep < 0) throw new Error(`line ${i + 1}: SET needs a key and a value`);
        cache.set(rest.slice(0, sep), rest.slice(sep + 1));
        break;
      }
      case 'GET':
        out.push(cache.get(rest) ?? 'NULL');
        break;
      case 'DEL':
        out.push(cache.delete(rest) ? '1' : '0');
        break;
      case 'SIZE':
        out.push(String(cache.size));
        break;
      default:
        throw new Error(`line ${i + 1}: unknown command ${JSON.stringify(command)}`);
    }
  }
  return out;
}

if (import.meta.main) {
  const output = run(readFileSync(0, 'latin1'));
  if (output.length > 0) process.stdout.write(output.join('\n') + '\n');
}
