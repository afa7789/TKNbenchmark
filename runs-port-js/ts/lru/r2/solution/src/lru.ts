import { readFileSync } from 'node:fs';

/**
 * Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
 * linked list stored in typed arrays. Every operation is O(1) expected.
 * Slot 0 is the list sentinel: next[0] is the most recently used entry,
 * prev[0] the least recently used.
 */
export class LRUCache<K, V> {
  readonly capacity: number;
  readonly #index = new Map<K, number>();
  readonly #keys: (K | undefined)[];
  readonly #values: (V | undefined)[];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  readonly #free: Int32Array;
  #freeCount: number;

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.capacity = capacity;
    this.#keys = new Array<K | undefined>(capacity + 1);
    this.#values = new Array<V | undefined>(capacity + 1);
    this.#prev = new Int32Array(capacity + 1);
    this.#next = new Int32Array(capacity + 1);
    this.#free = new Int32Array(capacity);
    this.#freeCount = capacity;
    for (let i = 0; i < capacity; i++) this.#free[i] = capacity - i;
  }

  get size(): number {
    return this.#index.size;
  }

  get(key: K): V | undefined {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#touch(slot);
    return this.#values[slot];
  }

  set(key: K, value: V): void {
    let slot = this.#index.get(key);
    if (slot !== undefined) {
      this.#values[slot] = value;
      this.#touch(slot);
      return;
    }
    if (this.#freeCount === 0) this.#remove(this.#prev[0]!);
    slot = this.#free[--this.#freeCount]!;
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#pushFront(slot);
  }

  delete(key: K): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #touch(slot: number): void {
    if (this.#next[0] === slot) return;
    this.#unlink(slot);
    this.#pushFront(slot);
  }

  #remove(slot: number): void {
    this.#index.delete(this.#keys[slot] as K);
    this.#unlink(slot);
    this.#keys[slot] = undefined;
    this.#values[slot] = undefined;
    this.#free[this.#freeCount++] = slot;
  }

  #unlink(slot: number): void {
    const p = this.#prev[slot]!;
    const n = this.#next[slot]!;
    this.#next[p] = n;
    this.#prev[n] = p;
  }

  #pushFront(slot: number): void {
    const first = this.#next[0]!;
    this.#prev[slot] = 0;
    this.#next[slot] = first;
    this.#prev[first] = slot;
    this.#next[0] = slot;
  }
}

/** Runs a full command script (capacity line followed by commands) and returns the output. */
export function run(input: string): string {
  const lines = input.split('\n');
  const capacity = Number.parseInt(lines[0] ?? '', 10);
  const cache = new LRUCache<string, string>(capacity);
  const out: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i]!;
    if (line.endsWith('\r')) line = line.slice(0, -1);
    if (line.length === 0) continue;

    const sp1 = line.indexOf(' ');
    const cmd = sp1 === -1 ? line : line.slice(0, sp1);
    switch (cmd) {
      case 'SET': {
        const sp2 = line.indexOf(' ', sp1 + 1);
        if (sp1 === -1 || sp2 === -1) break;
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

  return out.length > 0 ? out.join('\n') + '\n' : '';
}

function main(): void {
  const input = readFileSync(0, 'latin1');
  const output = run(input);
  if (output.length > 0) process.stdout.write(output, 'latin1');
}

if (import.meta.main) main();
