/**
 * A fixed-capacity least-recently-used cache.
 *
 * Entries live in slot arrays threaded by an intrusive doubly-linked list
 * (head = least recently used, tail = most recently used), with a Map from
 * key to slot index. Every operation is O(1) expected time.
 */
const NIL = -1;

export class LruCache {
  readonly #capacity: number;
  readonly #index = new Map<string, number>();
  #keys: string[] = [];
  #values: string[] = [];
  #prev: Int32Array;
  #next: Int32Array;
  #head = NIL;
  #tail = NIL;
  #freeSlots: number[] = [];

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.#capacity = capacity;
    const initial = Math.min(capacity + 1, 1024);
    this.#prev = new Int32Array(initial);
    this.#next = new Int32Array(initial);
  }

  get size(): number {
    return this.#index.size;
  }

  /** Returns the value for `key` and marks it most recently used, or `undefined` on a miss. */
  get(key: string): string | undefined {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#moveToTail(slot);
    return this.#values[slot];
  }

  /** Inserts or overwrites `key`, marks it most recently used, and evicts if over capacity. */
  set(key: string, value: string): void {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#moveToTail(existing);
      return;
    }
    const slot = this.#allocateSlot();
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#linkAtTail(slot);
    if (this.#index.size > this.#capacity) this.#removeSlot(this.#head);
  }

  /** Removes `key`; returns whether it was present. */
  delete(key: string): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#removeSlot(slot);
    return true;
  }

  #allocateSlot(): number {
    const reused = this.#freeSlots.pop();
    if (reused !== undefined) return reused;
    const slot = this.#keys.length;
    if (slot >= this.#prev.length) this.#grow();
    this.#keys.push('');
    this.#values.push('');
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

  #removeSlot(slot: number): void {
    this.#unlink(slot);
    this.#index.delete(this.#keys[slot]);
    this.#keys[slot] = '';
    this.#values[slot] = '';
    this.#freeSlots.push(slot);
  }

  #moveToTail(slot: number): void {
    if (slot === this.#tail) return;
    this.#unlink(slot);
    this.#linkAtTail(slot);
  }

  #linkAtTail(slot: number): void {
    this.#prev[slot] = this.#tail;
    this.#next[slot] = NIL;
    if (this.#tail === NIL) this.#head = slot;
    else this.#next[this.#tail] = slot;
    this.#tail = slot;
  }

  #unlink(slot: number): void {
    const prev = this.#prev[slot];
    const next = this.#next[slot];
    if (prev === NIL) this.#head = next;
    else this.#next[prev] = next;
    if (next === NIL) this.#tail = prev;
    else this.#prev[next] = prev;
  }
}
