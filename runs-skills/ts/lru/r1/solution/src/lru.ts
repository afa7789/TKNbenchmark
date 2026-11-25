/**
 * Least-recently-used cache backed by a Map, whose iteration order is
 * insertion order: the first key is the least recently used, the last key
 * the most recently used. Every operation is O(1) expected time.
 */
export class LruCache<K, V> {
  readonly capacity: number;
  readonly #entries = new Map<K, V>();

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.capacity = capacity;
  }

  get size(): number {
    return this.#entries.size;
  }

  get(key: K): V | undefined {
    const entries = this.#entries;
    if (!entries.has(key)) return undefined;
    const value = entries.get(key) as V;
    entries.delete(key);
    entries.set(key, value);
    return value;
  }

  set(key: K, value: V): void {
    const entries = this.#entries;
    entries.delete(key);
    entries.set(key, value);
    if (entries.size > this.capacity) {
      const oldest = entries.keys().next();
      if (!oldest.done) entries.delete(oldest.value);
    }
  }

  delete(key: K): boolean {
    return this.#entries.delete(key);
  }
}
