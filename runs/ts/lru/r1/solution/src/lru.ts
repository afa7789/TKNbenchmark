/**
 * A fixed-capacity least-recently-used cache.
 *
 * Backed by a single `Map`, whose iteration order is insertion order: the
 * first entry is the least recently used and the last is the most recently
 * used. Re-inserting a key moves it to the end, so every operation is O(1)
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
    if (!entries.has(key)) return undefined;
    const value = entries.get(key) as V;
    entries.delete(key);
    entries.set(key, value);
    return value;
  }

  /** Inserts or overwrites `key`, marking it most recently used and evicting if over capacity. */
  set(key: K, value: V): void {
    const entries = this.#entries;
    entries.delete(key);
    entries.set(key, value);
    if (entries.size > this.#capacity) {
      const oldest = entries.keys().next();
      if (!oldest.done) entries.delete(oldest.value);
    }
  }

  /** Removes `key`; returns whether it was present. */
  delete(key: K): boolean {
    return this.#entries.delete(key);
  }
}
