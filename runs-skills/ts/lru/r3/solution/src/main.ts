import { readFileSync } from 'node:fs';
import { LruCache } from './lru.ts';

/** Executes the command script and returns the output lines. */
export function run(input: string): string[] {
  const lines = input.split('\n');
  const capacity = Number.parseInt(lines[0] ?? '', 10);
  const cache = new LruCache(capacity);
  const out: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i] ?? '';
    if (line.endsWith('\r')) line = line.slice(0, -1);
    if (line === '') continue;

    const sp1 = line.indexOf(' ');
    const cmd = sp1 < 0 ? line : line.slice(0, sp1);
    switch (cmd) {
      case 'SET': {
        const sp2 = line.indexOf(' ', sp1 + 1);
        if (sp2 < 0) break;
        cache.set(line.slice(sp1 + 1, sp2), line.slice(sp2 + 1));
        break;
      }
      case 'GET':
        out.push(cache.get(line.slice(sp1 + 1)) ?? 'NULL');
        break;
      case 'DEL':
        out.push(cache.delete(line.slice(sp1 + 1)) ? '1' : '0');
        break;
      case 'SIZE':
        out.push(String(cache.size));
        break;
      default:
        break;
    }
  }
  return out;
}

if (import.meta.main) {
  const out = run(readFileSync(0, 'latin1'));
  if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
}
