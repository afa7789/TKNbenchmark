import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru-cache.js';

/**
 * Runs the command script and returns the output lines.
 * @param {string} input full standard input
 * @returns {string[]}
 */
export function run(input) {
  const lines = input.split('\n');
  const capacity = Number.parseInt(lines[0], 10);
  const cache = new LruCache(capacity);
  const out = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i];
    if (line.endsWith('\r')) line = line.slice(0, -1);
    if (line === '') continue;

    const sp1 = line.indexOf(' ');
    const command = sp1 === -1 ? line : line.slice(0, sp1);
    switch (command) {
      case 'SET': {
        const sp2 = line.indexOf(' ', sp1 + 1);
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
        throw new Error(`unknown command on line ${i + 1}: ${line}`);
    }
  }
  return out;
}

function writeAll(fd, text) {
  const buf = Buffer.from(text, 'latin1');
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(fd, buf, offset);
    } catch (err) {
      if (err.code !== 'EAGAIN') throw err;
    }
  }
}

if (import.meta.main) {
  const out = run(readFileSync(0, 'latin1'));
  if (out.length > 0) writeAll(1, out.join('\n') + '\n');
}
