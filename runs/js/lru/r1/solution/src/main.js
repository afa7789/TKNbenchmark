'use strict';

const fs = require('node:fs');
const { LRUCache } = require('./lru.js');

function run(input) {
  const lines = input.split('\n');
  const capacity = Number.parseInt(lines[0], 10);
  const cache = new LRUCache(capacity);
  const out = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i];
    if (line.endsWith('\r')) line = line.slice(0, -1);
    if (line === '') continue;

    const parts = line.split(' ');
    switch (parts[0]) {
      case 'SET':
        cache.set(parts[1], parts[2]);
        break;
      case 'GET': {
        const value = cache.get(parts[1]);
        out.push(value === undefined ? 'NULL' : value);
        break;
      }
      case 'DEL':
        out.push(cache.delete(parts[1]) ? '1' : '0');
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

function main() {
  const input = fs.readFileSync(0, 'latin1');
  const output = run(input);
  if (output) process.stdout.write(output);
}

main();
