const NONE = -1;

/**
 * Fixed-capacity LRU cache: a hash index over an intrusive doubly linked
 * recency list. Every operation runs in O(1) expected time.
 *
 * List nodes live in parallel arrays addressed by slot number. Since the cache
 * never holds more than `capacity` entries, at most `capacity + 1` slots are
 * ever needed, and freed slots are recycled through a free list.
 */
export class LruCache<K, V> {
  readonly #capacity: number;
  readonly #index = new Map<K, number>();
  readonly #keys: K[] = [];
  readonly #values: V[] = [];
  #prev: Int32Array;
  #next: Int32Array;
  #head = NONE; // most recently used
  #tail = NONE; // least recently used
  #freeSlots: number[] = [];

  constructor(capacity: number) {
    this.#capacity = capacity;
    const initial = Math.min(capacity + 1, 1024);
    this.#prev = new Int32Array(initial);
    this.#next = new Int32Array(initial);
  }

  get size(): number {
    return this.#index.size;
  }

  /** Inserts or overwrites `key`, making it the most recently used. */
  set(key: K, value: V): void {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#touch(existing);
      return;
    }

    const slot = this.#allocate();
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#pushFront(slot);
    this.#index.set(key, slot);

    if (this.#index.size > this.#capacity) this.#remove(this.#tail);
  }

  /** Returns the value for `key` (marking it most recently used), or `undefined` on a miss. */
  get(key: K): V | undefined {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#touch(slot);
    return this.#values[slot];
  }

  /** Removes `key`; returns whether it was present. */
  delete(key: K): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #allocate(): number {
    const recycled = this.#freeSlots.pop();
    if (recycled !== undefined) return recycled;
    const slot = this.#keys.length;
    if (slot === this.#prev.length) this.#grow();
    return slot;
  }

  #grow(): void {
    const length = Math.min(this.#prev.length * 2, this.#capacity + 1);
    const prev = new Int32Array(length);
    const next = new Int32Array(length);
    prev.set(this.#prev);
    next.set(this.#next);
    this.#prev = prev;
    this.#next = next;
  }

  #remove(slot: number): void {
    this.#index.delete(this.#keys[slot]);
    this.#unlink(slot);
    // Drop references so evicted entries can be garbage-collected.
    this.#keys[slot] = undefined as K;
    this.#values[slot] = undefined as V;
    this.#freeSlots.push(slot);
  }

  #touch(slot: number): void {
    if (slot === this.#head) return;
    this.#unlink(slot);
    this.#pushFront(slot);
  }

  #pushFront(slot: number): void {
    this.#prev[slot] = NONE;
    this.#next[slot] = this.#head;
    if (this.#head === NONE) this.#tail = slot;
    else this.#prev[this.#head] = slot;
    this.#head = slot;
  }

  #unlink(slot: number): void {
    const prev = this.#prev[slot];
    const next = this.#next[slot];
    if (prev === NONE) this.#head = next;
    else this.#next[prev] = next;
    if (next === NONE) this.#tail = prev;
    else this.#prev[next] = prev;
  }
}
