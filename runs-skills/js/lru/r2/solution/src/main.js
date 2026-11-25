import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru-cache.js';

const OUTPUT_CHUNK = 1 << 16;

/**
 * Runs the command script against an LRU cache and returns the output lines.
 * @param {string} input full program input
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

    const first = line.indexOf(' ');
    const command = first === -1 ? line : line.slice(0, first);
    switch (command) {
      case 'SET': {
        const second = line.indexOf(' ', first + 1);
        cache.set(line.slice(first + 1, second), line.slice(second + 1));
        break;
      }
      case 'GET':
        out.push(cache.get(line.slice(first + 1)) ?? 'NULL');
        break;
      case 'DEL':
        out.push(cache.delete(line.slice(first + 1)) ? '1' : '0');
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
  for (let i = 0; i < out.length; i += OUTPUT_CHUNK) {
    writeAll(1, out.slice(i, i + OUTPUT_CHUNK).join('\n') + '\n');
  }
}
