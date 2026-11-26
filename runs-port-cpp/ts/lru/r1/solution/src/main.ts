// LRU cache simulator: reads a capacity and a stream of commands from stdin.
import { readFileSync } from 'node:fs';

/**
 * Least-recently-used cache backed by a Map, whose iteration order is insertion
 * order: re-inserting a key moves it to the back (most recently used), and the
 * first key is always the least recently used. Every operation is O(1) expected.
 */
export class LruCache {
  readonly #capacity: number;
  readonly #entries = new Map<string, string>();

  constructor(capacity: number) {
    this.#capacity = capacity;
  }

  set(key: string, value: string): void {
    this.#entries.delete(key);
    this.#entries.set(key, value);
    if (this.#entries.size > this.#capacity) {
      const oldest = this.#entries.keys().next();
      if (!oldest.done) this.#entries.delete(oldest.value);
    }
  }

  get(key: string): string | undefined {
    const value = this.#entries.get(key);
    if (value === undefined) return undefined;
    this.#entries.delete(key);
    this.#entries.set(key, value);
    return value;
  }

  delete(key: string): boolean {
    return this.#entries.delete(key);
  }

  get size(): number {
    return this.#entries.size;
  }
}

/** Strips trailing CR/space/tab and leading space/tab. */
function trim(line: string): string {
  return line.replace(/[\r \t]+$/, '').replace(/^[ \t]+/, '');
}

/** Parses the leading decimal digits of `text`; 0 if there are none. */
function parseCapacity(text: string): number {
  const match = /^\d+/.exec(text);
  return match ? Number(match[0]) : 0;
}

function* lines(input: string): Generator<string> {
  let start = 0;
  while (start < input.length) {
    let end = input.indexOf('\n', start);
    if (end === -1) end = input.length;
    yield trim(input.slice(start, end));
    start = end + 1;
  }
}

export function run(input: string): string {
  const lineIter = lines(input);
  const first = lineIter.next();
  const cache = new LruCache(first.done ? 0 : parseCapacity(first.value));
  const out: string[] = [];

  for (const line of lineIter) {
    const [cmd, key = '', value = ''] = line.split(' ', 3);
    switch (cmd) {
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
    }
  }

  return out.length > 0 ? out.join('\n') + '\n' : '';
}

const input = readFileSync(0, 'latin1');
process.stdout.write(Buffer.from(run(input), 'latin1'));
