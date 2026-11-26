/**
 * Fixed-capacity LRU cache keyed by strings.
 *
 * Built on `Map`, whose iteration order is insertion order: the first key is
 * the least recently used and the last is the most recently used. Re-inserting
 * a key moves it to the end, so every operation runs in O(1) expected time.
 */
export class LruCache<V> {
  readonly #capacity: number
  readonly #entries = new Map<string, V>()

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`)
    }
    this.#capacity = capacity
  }

  get size(): number {
    return this.#entries.size
  }

  /** Insert or overwrite; the key becomes the most recently used. */
  set(key: string, value: V): void {
    const entries = this.#entries
    if (entries.has(key)) {
      entries.delete(key)
    } else if (entries.size >= this.#capacity) {
      // Evicting before inserting is observably identical to inserting and
      // then evicting, and keeps the map bounded by the capacity.
      const oldest = entries.keys().next()
      if (!oldest.done) entries.delete(oldest.value)
    }
    entries.set(key, value)
  }

  /** On hit, mark the key most recently used and return its value. */
  get(key: string): V | undefined {
    const entries = this.#entries
    const value = entries.get(key)
    if (value === undefined && !entries.has(key)) return undefined
    entries.delete(key)
    entries.set(key, value as V)
    return value
  }

  /** Remove the key; return whether it was present. */
  delete(key: string): boolean {
    return this.#entries.delete(key)
  }
}
