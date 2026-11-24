const NIL = -1;

/**
 * Fixed-capacity LRU cache with O(1) expected-time operations.
 *
 * Entries live in preallocated slots; recency order is an intrusive doubly
 * linked list over slot indices (typed arrays), and a Map resolves keys to slots.
 */
export class LruCache {
  readonly capacity: number;

  readonly #index = new Map<string, number>();
  readonly #keys: string[] = [];
  readonly #values: string[] = [];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  readonly #freeSlots: number[] = [];
  #head = NIL; // most recently used
  #tail = NIL; // least recently used

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.capacity = capacity;
    this.#prev = new Int32Array(capacity);
    this.#next = new Int32Array(capacity);
  }

  get size(): number {
    return this.#index.size;
  }

  get(key: string): string | undefined {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#moveToFront(slot);
    return this.#values[slot];
  }

  set(key: string, value: string): void {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#moveToFront(existing);
      return;
    }
    if (this.#index.size >= this.capacity) this.#evictLeastRecent();

    const slot = this.#freeSlots.pop() ?? this.#keys.length;
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#pushFront(slot);
  }

  delete(key: string): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#removeSlot(slot);
    return true;
  }

  #evictLeastRecent(): void {
    if (this.#tail !== NIL) this.#removeSlot(this.#tail);
  }

  #removeSlot(slot: number): void {
    this.#index.delete(this.#keys[slot]);
    this.#unlink(slot);
    this.#keys[slot] = '';
    this.#values[slot] = '';
    this.#freeSlots.push(slot);
  }

  #moveToFront(slot: number): void {
    if (slot === this.#head) return;
    this.#unlink(slot);
    this.#pushFront(slot);
  }

  #pushFront(slot: number): void {
    this.#prev[slot] = NIL;
    this.#next[slot] = this.#head;
    if (this.#head !== NIL) this.#prev[this.#head] = slot;
    this.#head = slot;
    if (this.#tail === NIL) this.#tail = slot;
  }

  #unlink(slot: number): void {
    const p = this.#prev[slot];
    const n = this.#next[slot];
    if (p !== NIL) this.#next[p] = n;
    else this.#head = n;
    if (n !== NIL) this.#prev[n] = p;
    else this.#tail = p;
  }
}
