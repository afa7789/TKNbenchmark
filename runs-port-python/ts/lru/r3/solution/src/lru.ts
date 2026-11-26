/**
 * Simulate an LRU cache driven by commands read from standard input.
 *
 * The cache is a hash map from key to slot index plus an intrusive doubly
 * linked list over preallocated typed arrays, so every command is O(1).
 */

import { readFileSync, writeSync } from 'node:fs';

const NIL = -1;

export class LruCache {
  readonly capacity: number;
  readonly #index = new Map<string, number>();
  readonly #keys: string[];
  readonly #values: string[];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  readonly #free: number[] = [];
  #used = 0;
  /** Most recently used slot. */
  #head = NIL;
  /** Least recently used slot. */
  #tail = NIL;

  constructor(capacity: number) {
    if (!Number.isSafeInteger(capacity) || capacity < 1) {
      throw new RangeError(`invalid capacity: ${capacity}`);
    }
    this.capacity = capacity;
    // One extra slot: an insert briefly holds capacity + 1 entries before eviction.
    const slots = capacity + 1;
    this.#keys = new Array<string>(slots);
    this.#values = new Array<string>(slots);
    this.#prev = new Int32Array(slots);
    this.#next = new Int32Array(slots);
  }

  get size(): number {
    return this.#index.size;
  }

  get(key: string): string | undefined {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#moveToFront(slot);
    return this.#values[slot];
  }

  set(key: string, value: string): void {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#moveToFront(existing);
      return;
    }
    const slot = this.#allocate();
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#pushFront(slot);
    if (this.#index.size > this.capacity) this.#remove(this.#tail);
  }

  delete(key: string): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #allocate(): number {
    return this.#free.pop() ?? this.#used++;
  }

  #remove(slot: number): void {
    this.#unlink(slot);
    this.#index.delete(this.#keys[slot]);
    this.#keys[slot] = '';
    this.#values[slot] = '';
    this.#free.push(slot);
  }

  #moveToFront(slot: number): void {
    if (slot === this.#head) return;
    this.#unlink(slot);
    this.#pushFront(slot);
  }

  #pushFront(slot: number): void {
    this.#prev[slot] = NIL;
    this.#next[slot] = this.#head;
    if (this.#head !== NIL) this.#prev[this.#head] = slot;
    else this.#tail = slot;
    this.#head = slot;
  }

  #unlink(slot: number): void {
    const prev = this.#prev[slot];
    const next = this.#next[slot];
    if (prev !== NIL) this.#next[prev] = next;
    else this.#head = next;
    if (next !== NIL) this.#prev[next] = prev;
    else this.#tail = prev;
  }
}

const WHITESPACE = /\s+/;

/** Execute the command stream in `input` and return the output text. */
export function run(input: string): string {
  const lines = input.split('\n');
  const header = lines[0]?.trim() ?? '';
  if (header === '') return '';
  const capacity = Number(header);
  if (!Number.isInteger(capacity)) throw new Error(`invalid capacity line: ${header}`);

  const cache = new LruCache(capacity);
  const out: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line === '') continue;
    const [cmd, key, value] = line.split(WHITESPACE);
    switch (cmd) {
      case 'GET':
        out.push(cache.get(key) ?? 'NULL');
        break;
      case 'SET':
        cache.set(key, value);
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

  return out.length === 0 ? '' : out.join('\n') + '\n';
}

function writeAll(fd: number, data: Buffer): void {
  let offset = 0;
  while (offset < data.length) {
    try {
      offset += writeSync(fd, data, offset);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'EAGAIN') throw err;
    }
  }
}

function main(): number {
  // latin1 maps bytes 1:1 to code units, so arbitrary input round-trips exactly.
  const input = readFileSync(0).toString('latin1');
  writeAll(1, Buffer.from(run(input), 'latin1'));
  return 0;
}

process.exitCode = main();
