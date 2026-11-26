/** Sentinel slot index meaning "no slot". */
const NONE = -1;

/**
 * A fixed-capacity cache that evicts the least recently used entry.
 *
 * Entries live in preallocated slots linked into a doubly linked recency list
 * (head = most recently used, tail = least recently used); a `Map` indexes slots by key.
 * All operations run in O(1) expected time.
 */
export class LruCache<K, V> {
  readonly #capacity: number;
  readonly #index = new Map<K, number>();
  readonly #keys: (K | undefined)[] = [];
  readonly #values: (V | undefined)[] = [];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  #head = NONE;
  #tail = NONE;
  /** Slots released by `delete`, available for reuse. */
  readonly #free: number[] = [];

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer: ${capacity}`);
    }
    this.#capacity = capacity;
    this.#prev = new Int32Array(capacity);
    this.#next = new Int32Array(capacity);
  }

  /** Inserts or overwrites a mapping, making the key the most recently used. */
  set(key: K, value: V): void {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#moveToFront(existing);
      return;
    }
    let slot: number;
    if (this.#index.size < this.#capacity) {
      slot = this.#free.pop() ?? this.#keys.length;
    } else {
      // Full: reuse the least recently used entry's slot.
      slot = this.#tail;
      this.#unlink(slot);
      this.#index.delete(this.#keys[slot] as K);
    }
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#pushFront(slot);
  }

  /** Returns the value for the key (marking it most recently used), or `undefined` if absent. */
  get(key: K): V | undefined {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#moveToFront(slot);
    return this.#values[slot];
  }

  /** Removes the key, returning whether it was present. */
  delete(key: K): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#index.delete(key);
    this.#unlink(slot);
    this.#keys[slot] = undefined;
    this.#values[slot] = undefined;
    this.#free.push(slot);
    return true;
  }

  get size(): number {
    return this.#index.size;
  }

  #moveToFront(slot: number): void {
    if (slot === this.#head) return;
    this.#unlink(slot);
    this.#pushFront(slot);
  }

  #pushFront(slot: number): void {
    this.#prev[slot] = NONE;
    this.#next[slot] = this.#head;
    if (this.#head !== NONE) this.#prev[this.#head] = slot;
    else this.#tail = slot;
    this.#head = slot;
  }

  #unlink(slot: number): void {
    const before = this.#prev[slot];
    const after = this.#next[slot];
    if (before !== NONE) this.#next[before] = after;
    else this.#head = after;
    if (after !== NONE) this.#prev[after] = before;
    else this.#tail = before;
  }
}
