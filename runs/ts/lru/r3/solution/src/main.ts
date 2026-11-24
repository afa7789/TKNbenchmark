import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru-cache.ts';

const NULL_REPLY = 'NULL';

/** Runs the command script and returns the output lines. */
export function run(input: string): string[] {
  const lines = input.split('\n');
  const capacity = Number.parseInt(lines[0] ?? '', 10);
  if (!Number.isInteger(capacity) || capacity < 1) return [];

  const cache = new LruCache(capacity);
  const out: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i];
    if (line.endsWith('\r')) line = line.slice(0, -1);
    if (line === '') continue;

    const firstSpace = line.indexOf(' ');
    const command = firstSpace === -1 ? line : line.slice(0, firstSpace);
    const rest = firstSpace === -1 ? '' : line.slice(firstSpace + 1);

    switch (command) {
      case 'SET': {
        const sep = rest.indexOf(' ');
        if (sep === -1) break;
        cache.set(rest.slice(0, sep), rest.slice(sep + 1));
        break;
      }
      case 'GET':
        out.push(cache.get(rest) ?? NULL_REPLY);
        break;
      case 'DEL':
        out.push(cache.delete(rest) ? '1' : '0');
        break;
      case 'SIZE':
        out.push(String(cache.size));
        break;
      default:
        // Unknown commands are ignored.
        break;
    }
  }
  return out;
}

function writeAll(fd: number, text: string): void {
  const buf = Buffer.from(text, 'latin1');
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(fd, buf, offset, buf.length - offset);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'EAGAIN') continue;
      throw err;
    }
  }
}

const output = run(readFileSync(0, 'latin1'));
if (output.length > 0) writeAll(1, output.join('\n') + '\n');
