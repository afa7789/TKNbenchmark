/**
 * LRU cache backed by a Map. A JavaScript Map iterates in insertion order,
 * so re-inserting a key on access moves it to the most-recently-used end and
 * the first key is always the least recently used. All operations are O(1)
 * expected time.
 */
export class LruCache<K, V> {
  readonly #capacity: number;
  readonly #entries = new Map<K, V>();

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.#capacity = capacity;
  }

  get size(): number {
    return this.#entries.size;
  }

  /** Returns the value for `key` and marks it most recently used. */
  get(key: K): V | undefined {
    const entries = this.#entries;
    const value = entries.get(key);
    if (value !== undefined) {
      entries.delete(key);
      entries.set(key, value);
    }
    return value;
  }

  /** Inserts or overwrites `key`, evicting the LRU entry when over capacity. */
  set(key: K, value: V): void {
    const entries = this.#entries;
    entries.delete(key);
    entries.set(key, value);
    if (entries.size > this.#capacity) {
      const eldest = entries.keys().next();
      if (!eldest.done) entries.delete(eldest.value);
    }
  }

  /** Removes `key`; returns whether it was present. */
  delete(key: K): boolean {
    return this.#entries.delete(key);
  }
}
