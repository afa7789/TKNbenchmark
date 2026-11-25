#!/usr/bin/env node
import { readFileSync, writeSync } from 'node:fs';
import { LRUCache } from './lru-cache.js';

/**
 * Runs the command script in `input` and returns the output lines.
 * @param {string} input full standard input
 * @returns {string[]}
 */
export function run(input) {
  const lines = input.split('\n');
  const capacity = Number.parseInt(lines[0], 10);
  const cache = new LRUCache(capacity);
  const out = [];

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
        // Unknown commands are ignored.
        break;
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
