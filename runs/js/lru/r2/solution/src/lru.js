'use strict';

const fs = require('node:fs');

/**
 * Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
 * linked list stored in typed arrays. Every operation is O(1) expected.
 * Slot 0 is the list sentinel: next[0] is the most recently used entry,
 * prev[0] the least recently used.
 */
class LRUCache {
  constructor(capacity) {
    this.capacity = capacity;
    this.index = new Map();
    this.keys = new Array(capacity + 1);
    this.values = new Array(capacity + 1);
    this.prev = new Int32Array(capacity + 1);
    this.next = new Int32Array(capacity + 1);
    this.free = new Int32Array(capacity);
    this.freeCount = capacity;
    for (let i = 0; i < capacity; i++) this.free[i] = capacity - i;
  }

  get size() {
    return this.index.size;
  }

  get(key) {
    const slot = this.index.get(key);
    if (slot === undefined) return undefined;
    this.#unlink(slot);
    this.#pushFront(slot);
    return this.values[slot];
  }

  set(key, value) {
    let slot = this.index.get(key);
    if (slot !== undefined) {
      this.values[slot] = value;
      this.#unlink(slot);
      this.#pushFront(slot);
      return;
    }
    if (this.freeCount === 0) this.#remove(this.prev[0]);
    slot = this.free[--this.freeCount];
    this.keys[slot] = key;
    this.values[slot] = value;
    this.index.set(key, slot);
    this.#pushFront(slot);
  }

  delete(key) {
    const slot = this.index.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #remove(slot) {
    this.index.delete(this.keys[slot]);
    this.#unlink(slot);
    this.keys[slot] = undefined;
    this.values[slot] = undefined;
    this.free[this.freeCount++] = slot;
  }

  #unlink(slot) {
    const p = this.prev[slot];
    const n = this.next[slot];
    this.next[p] = n;
    this.prev[n] = p;
  }

  #pushFront(slot) {
    const first = this.next[0];
    this.prev[slot] = 0;
    this.next[slot] = first;
    this.prev[first] = slot;
    this.next[0] = slot;
  }
}

function run(input) {
  const lines = input.split('\n');
  const capacity = Number.parseInt(lines[0], 10);
  const cache = new LRUCache(capacity);
  const out = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i];
    if (line.endsWith('\r')) line = line.slice(0, -1);
    if (line.length === 0) continue;

    const sp1 = line.indexOf(' ');
    const cmd = sp1 === -1 ? line : line.slice(0, sp1);
    switch (cmd) {
      case 'SET': {
        const sp2 = line.indexOf(' ', sp1 + 1);
        cache.set(line.slice(sp1 + 1, sp2), line.slice(sp2 + 1));
        break;
      }
      case 'GET': {
        const value = cache.get(line.slice(sp1 + 1));
        out.push(value === undefined ? 'NULL' : value);
        break;
      }
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

  return out.length > 0 ? out.join('\n') + '\n' : '';
}

function main() {
  const input = fs.readFileSync(0, 'latin1');
  const output = run(input);
  if (output.length > 0) process.stdout.write(output, 'latin1');
}

if (require.main === module) main();

module.exports = { LRUCache, run };
