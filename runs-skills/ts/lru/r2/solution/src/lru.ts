/**
 * Fixed-capacity LRU cache backed by a hash map and an index-based doubly
 * linked list stored in typed arrays. All operations run in O(1) expected time.
 */
export class LruCache {
  readonly capacity: number;
  readonly #index = new Map<string, number>();
  readonly #keys: string[];
  readonly #values: string[];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  /** Most recently used slot, or -1 when empty. */
  #head = -1;
  /** Least recently used slot, or -1 when empty. */
  #tail = -1;
  /** Next never-used slot. */
  #fresh = 0;
  /** Stack of released slots available for reuse. */
  readonly #free: number[] = [];

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.capacity = capacity;
    this.#keys = new Array<string>(capacity);
    this.#values = new Array<string>(capacity);
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
    if (this.#index.size >= this.capacity) this.#evict();
    const slot = this.#allocate();
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#pushFront(slot);
  }

  delete(key: string): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#index.delete(key);
    this.#release(slot);
    return true;
  }

  #allocate(): number {
    return this.#free.pop() ?? this.#fresh++;
  }

  #release(slot: number): void {
    this.#unlink(slot);
    this.#keys[slot] = '';
    this.#values[slot] = '';
    this.#free.push(slot);
  }

  #evict(): void {
    const slot = this.#tail;
    if (slot < 0) return;
    const key = this.#keys[slot];
    if (key !== undefined) this.#index.delete(key);
    this.#release(slot);
  }

  #unlink(slot: number): void {
    const prev = this.#prev[slot] ?? -1;
    const next = this.#next[slot] ?? -1;
    if (prev >= 0) this.#next[prev] = next;
    else this.#head = next;
    if (next >= 0) this.#prev[next] = prev;
    else this.#tail = prev;
  }

  #pushFront(slot: number): void {
    this.#prev[slot] = -1;
    this.#next[slot] = this.#head;
    if (this.#head >= 0) this.#prev[this.#head] = slot;
    else this.#tail = slot;
    this.#head = slot;
  }

  #moveToFront(slot: number): void {
    if (slot === this.#head) return;
    this.#unlink(slot);
    this.#pushFront(slot);
  }
}
