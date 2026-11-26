/**
 * A fixed-capacity least-recently-used cache.
 *
 * Entries live in a doubly linked list backed by typed arrays (index-based, so no
 * per-node allocation), with a Map from key to slot. Every operation is O(1) expected.
 */
const NONE = -1;

export class LruCache {
  readonly #capacity: number;
  readonly #index = new Map<string, number>();
  #keys: string[] = [];
  #values: string[] = [];
  #prev: Int32Array;
  #next: Int32Array;
  /** Least recently used slot. */
  #head = NONE;
  /** Most recently used slot. */
  #tail = NONE;
  /** Slots freed by deletion, available for reuse. */
  #free: number[] = [];
  #used = 0;

  constructor(capacity: number) {
    this.#capacity = capacity;
    const initial = Math.max(16, Math.min(capacity, 1 << 16));
    this.#prev = new Int32Array(initial);
    this.#next = new Int32Array(initial);
  }

  get size(): number {
    return this.#index.size;
  }

  get(key: string): string | undefined {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#moveToTail(slot);
    return this.#values[slot];
  }

  set(key: string, value: string): void {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#moveToTail(existing);
      return;
    }
    const slot = this.#allocate();
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#linkTail(slot);
    if (this.#index.size > this.#capacity) this.#evictHead();
  }

  delete(key: string): boolean {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #evictHead(): void {
    if (this.#head !== NONE) this.#remove(this.#head);
  }

  #remove(slot: number): void {
    this.#index.delete(this.#keys[slot]);
    this.#unlink(slot);
    this.#keys[slot] = "";
    this.#values[slot] = "";
    this.#free.push(slot);
  }

  #allocate(): number {
    const reused = this.#free.pop();
    if (reused !== undefined) return reused;
    const slot = this.#used++;
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

  #moveToTail(slot: number): void {
    if (slot === this.#tail) return;
    this.#unlink(slot);
    this.#linkTail(slot);
  }

  #linkTail(slot: number): void {
    this.#prev[slot] = this.#tail;
    this.#next[slot] = NONE;
    if (this.#tail === NONE) this.#head = slot;
    else this.#next[this.#tail] = slot;
    this.#tail = slot;
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
