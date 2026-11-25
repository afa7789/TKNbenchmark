/**
 * Fixed-capacity LRU cache backed by a hash map and an intrusive doubly linked
 * list stored in typed arrays. Every operation runs in O(1) expected time.
 */
export class LruCache {
  readonly capacity: number;
  readonly #index = new Map<string, number>();
  readonly #keys: string[];
  readonly #values: string[];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  /** Slot 0 is the list sentinel: next[0] is the MRU entry, prev[0] the LRU one. */
  static readonly #HEAD = 0;
  readonly #free: number[] = [];
  #used = 1;

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.capacity = capacity;
    const slots = capacity + 1;
    this.#keys = new Array<string>(slots).fill('');
    this.#values = new Array<string>(slots).fill('');
    this.#prev = new Int32Array(slots);
    this.#next = new Int32Array(slots);
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
    if (this.#index.size >= this.capacity) {
      this.#remove(this.#prev[LruCache.#HEAD] ?? LruCache.#HEAD);
    }
    const slot = this.#free.pop() ?? this.#used++;
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#linkFront(slot);
  }

  delete(key: string): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #remove(slot: number): void {
    this.#unlink(slot);
    this.#index.delete(this.#keys[slot] ?? '');
    this.#keys[slot] = '';
    this.#values[slot] = '';
    this.#free.push(slot);
  }

  #unlink(slot: number): void {
    const p = this.#prev[slot] ?? 0;
    const n = this.#next[slot] ?? 0;
    this.#next[p] = n;
    this.#prev[n] = p;
  }

  #linkFront(slot: number): void {
    const head = LruCache.#HEAD;
    const first = this.#next[head] ?? head;
    this.#prev[slot] = head;
    this.#next[slot] = first;
    this.#prev[first] = slot;
    this.#next[head] = slot;
  }

  #moveToFront(slot: number): void {
    if (this.#next[LruCache.#HEAD] === slot) return;
    this.#unlink(slot);
    this.#linkFront(slot);
  }
}
