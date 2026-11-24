/**
 * Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
 * linked list stored in typed arrays. All operations are O(1) expected.
 */
const NIL = -1;

export class LruCache {
  readonly #capacity: number;
  readonly #index = new Map<string, number>();
  readonly #keys: string[];
  readonly #values: string[];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  #head = NIL; // most recently used
  #tail = NIL; // least recently used
  #freeTop = NIL; // stack of reusable slots, linked through #next
  #used = 0; // slots handed out so far (high-water mark)

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`invalid capacity: ${capacity}`);
    }
    this.#capacity = capacity;
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
    if (this.#index.size >= this.#capacity) this.#evict();
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
    this.#unlink(slot);
    this.#release(slot);
    return true;
  }

  #evict(): void {
    const slot = this.#tail;
    this.#index.delete(this.#keys[slot]);
    this.#unlink(slot);
    this.#release(slot);
  }

  #allocate(): number {
    if (this.#freeTop !== NIL) {
      const slot = this.#freeTop;
      this.#freeTop = this.#next[slot];
      return slot;
    }
    return this.#used++;
  }

  #release(slot: number): void {
    // Drop references so evicted strings can be collected.
    this.#keys[slot] = "";
    this.#values[slot] = "";
    this.#next[slot] = this.#freeTop;
    this.#freeTop = slot;
  }

  #pushFront(slot: number): void {
    this.#prev[slot] = NIL;
    this.#next[slot] = this.#head;
    if (this.#head !== NIL) this.#prev[this.#head] = slot;
    else this.#tail = slot;
    this.#head = slot;
  }

  #unlink(slot: number): void {
    const p = this.#prev[slot];
    const n = this.#next[slot];
    if (p !== NIL) this.#next[p] = n;
    else this.#head = n;
    if (n !== NIL) this.#prev[n] = p;
    else this.#tail = p;
  }

  #moveToFront(slot: number): void {
    if (slot === this.#head) return;
    this.#unlink(slot);
    this.#pushFront(slot);
  }
}
