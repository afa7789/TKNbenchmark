const NONE = -1;

/**
 * Fixed-capacity least-recently-used cache with O(1) expected-time operations.
 *
 * Entries live in a pool of slots linked into a doubly linked list ordered from
 * most (head) to least (tail) recently used. A Map indexes keys to slots. Freed
 * slots are recycled through a free list, so the pool never exceeds capacity + 1.
 */
export class LruCache {
  readonly capacity: number;

  readonly #index = new Map<string, number>();
  readonly #keys: string[] = [];
  readonly #values: string[] = [];
  #prev: Int32Array;
  #next: Int32Array;
  #head = NONE;
  #tail = NONE;
  #freeSlots: number[] = [];
  #allocated = 0;

  constructor(capacity: number) {
    this.capacity = capacity;
    const initial = Math.min(capacity + 1, 1 << 16);
    this.#prev = new Int32Array(initial);
    this.#next = new Int32Array(initial);
  }

  get size(): number {
    return this.#index.size;
  }

  /** Inserts or overwrites `key`, making it the most recently used entry. */
  set(key: string, value: string): void {
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
    if (this.#index.size > this.capacity) {
      this.#remove(this.#tail);
    }
  }

  /** Returns the value for `key` and marks it most recently used, or undefined on a miss. */
  get(key: string): string | undefined {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#touch(slot);
    return this.#values[slot];
  }

  /** Removes `key`; returns whether it was present. */
  delete(key: string): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #allocate(): number {
    const recycled = this.#freeSlots.pop();
    if (recycled !== undefined) return recycled;
    const slot = this.#allocated++;
    if (slot >= this.#prev.length) this.#grow();
    return slot;
  }

  #grow(): void {
    const length = this.#prev.length * 2;
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
    this.#keys[slot] = '';
    this.#values[slot] = '';
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
    if (this.#head !== NONE) this.#prev[this.#head] = slot;
    else this.#tail = slot;
    this.#head = slot;
  }

  #unlink(slot: number): void {
    const prev = this.#prev[slot];
    const next = this.#next[slot];
    if (prev !== NONE) this.#next[prev] = next;
    else this.#head = next;
    if (next !== NONE) this.#prev[next] = prev;
    else this.#tail = prev;
  }
}
