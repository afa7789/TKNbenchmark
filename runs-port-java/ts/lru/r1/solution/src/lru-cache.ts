/** A node in the recency list. */
interface Entry<K, V> {
  key: K;
  value: V;
  prev: Entry<K, V> | null;
  next: Entry<K, V> | null;
}

/**
 * A fixed-capacity least-recently-used cache.
 *
 * Backed by a hash map plus a doubly linked recency list, so lookups,
 * insertions, overwrites, evictions and removals all run in O(1) expected
 * time. Both {@link get} and {@link set} mark the key as most recently used.
 */
export class LruCache<K, V> {
  readonly capacity: number;
  readonly #entries = new Map<K, Entry<K, V>>();
  /** Least recently used entry. */
  #head: Entry<K, V> | null = null;
  /** Most recently used entry. */
  #tail: Entry<K, V> | null = null;

  constructor(capacity: number) {
    if (!Number.isSafeInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer: ${capacity}`);
    }
    this.capacity = capacity;
  }

  get size(): number {
    return this.#entries.size;
  }

  /** Returns the value for `key`, or `undefined` if absent; a hit refreshes recency. */
  get(key: K): V | undefined {
    const entry = this.#entries.get(key);
    if (entry === undefined) return undefined;
    this.#moveToTail(entry);
    return entry.value;
  }

  /** Inserts or overwrites `key`, making it most recently used and evicting if over capacity. */
  set(key: K, value: V): void {
    const existing = this.#entries.get(key);
    if (existing !== undefined) {
      existing.value = value;
      this.#moveToTail(existing);
      return;
    }
    const entry: Entry<K, V> = { key, value, prev: null, next: null };
    this.#entries.set(key, entry);
    this.#append(entry);
    if (this.#entries.size > this.capacity) {
      const eldest = this.#head!;
      this.#unlink(eldest);
      this.#entries.delete(eldest.key);
    }
  }

  /** Removes `key`; returns `true` if it was present. */
  delete(key: K): boolean {
    const entry = this.#entries.get(key);
    if (entry === undefined) return false;
    this.#unlink(entry);
    this.#entries.delete(key);
    return true;
  }

  #moveToTail(entry: Entry<K, V>): void {
    if (entry === this.#tail) return;
    this.#unlink(entry);
    this.#append(entry);
  }

  #append(entry: Entry<K, V>): void {
    entry.prev = this.#tail;
    entry.next = null;
    if (this.#tail === null) this.#head = entry;
    else this.#tail.next = entry;
    this.#tail = entry;
  }

  #unlink(entry: Entry<K, V>): void {
    const { prev, next } = entry;
    if (prev === null) this.#head = next;
    else prev.next = next;
    if (next === null) this.#tail = prev;
    else next.prev = prev;
    entry.prev = null;
    entry.next = null;
  }
}
