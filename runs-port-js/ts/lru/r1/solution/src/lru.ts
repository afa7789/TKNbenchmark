const NIL = -1;

/**
 * Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
 * linked list stored in typed arrays. All operations are O(1) expected.
 */
export class LRUCache<K, V> {
  readonly capacity: number;
  readonly #index = new Map<K, number>(); // key -> slot
  readonly #keys: (K | undefined)[];
  readonly #values: (V | undefined)[];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  readonly #freeList: number[] = [];
  #head = NIL; // most recently used
  #tail = NIL; // least recently used
  #nextUnused = 0;

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.capacity = capacity;
    this.#keys = new Array<K | undefined>(capacity);
    this.#values = new Array<V | undefined>(capacity);
    this.#prev = new Int32Array(capacity);
    this.#next = new Int32Array(capacity);
  }

  get size(): number {
    return this.#index.size;
  }

  get(key: K): V | undefined {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#moveToFront(slot);
    return this.#values[slot];
  }

  set(key: K, value: V): void {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#moveToFront(existing);
      return;
    }
    if (this.#index.size >= this.capacity) this.#release(this.#tail);
    const slot = this.#freeList.pop() ?? this.#nextUnused++;
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#pushFront(slot);
  }

  delete(key: K): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#release(slot);
    return true;
  }

  #release(slot: number): void {
    this.#unlink(slot);
    this.#index.delete(this.#keys[slot] as K);
    this.#keys[slot] = undefined;
    this.#values[slot] = undefined;
    this.#freeList.push(slot);
  }

  #unlink(slot: number): void {
    const p = this.#prev[slot];
    const n = this.#next[slot];
    if (p === NIL) this.#head = n;
    else this.#next[p] = n;
    if (n === NIL) this.#tail = p;
    else this.#prev[n] = p;
  }

  #pushFront(slot: number): void {
    this.#prev[slot] = NIL;
    this.#next[slot] = this.#head;
    if (this.#head === NIL) this.#tail = slot;
    else this.#prev[this.#head] = slot;
    this.#head = slot;
  }

  #moveToFront(slot: number): void {
    if (slot === this.#head) return;
    this.#unlink(slot);
    this.#pushFront(slot);
  }
}
