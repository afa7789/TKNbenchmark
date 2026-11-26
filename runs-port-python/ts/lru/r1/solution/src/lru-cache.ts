/**
 * A fixed-capacity least-recently-used cache.
 *
 * Entries live in a doubly linked list backed by typed arrays (index 0 is the
 * sentinel), with a Map from key to node index. Every operation is O(1).
 */
export class LruCache<V> {
  readonly capacity: number;

  readonly #index = new Map<string, number>();
  readonly #keys: string[];
  readonly #values: (V | undefined)[];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  #free: number[] = [];
  #allocated = 1;

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.capacity = capacity;
    // One extra slot for the sentinel and one for the transient overflow entry.
    const slots = capacity + 2;
    this.#keys = new Array<string>(slots);
    this.#values = new Array<V | undefined>(slots);
    this.#prev = new Int32Array(slots);
    this.#next = new Int32Array(slots);
  }

  get size(): number {
    return this.#index.size;
  }

  /** Returns the value for `key`, marking it most recently used, or undefined. */
  get(key: string): V | undefined {
    const node = this.#index.get(key);
    if (node === undefined) return undefined;
    this.#unlink(node);
    this.#pushFront(node);
    return this.#values[node];
  }

  /** Inserts or overwrites `key`, marking it most recently used; evicts if over capacity. */
  set(key: string, value: V): void {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#unlink(existing);
      this.#pushFront(existing);
      return;
    }
    const node = this.#allocate();
    this.#keys[node] = key;
    this.#values[node] = value;
    this.#index.set(key, node);
    this.#pushFront(node);
    if (this.#index.size > this.capacity) {
      this.#remove(this.#prev[0]);
    }
  }

  /** Removes `key`; returns whether it was present. */
  delete(key: string): boolean {
    const node = this.#index.get(key);
    if (node === undefined) return false;
    this.#remove(node);
    return true;
  }

  #allocate(): number {
    return this.#free.pop() ?? this.#allocated++;
  }

  #remove(node: number): void {
    this.#unlink(node);
    this.#index.delete(this.#keys[node]);
    this.#keys[node] = "";
    this.#values[node] = undefined;
    this.#free.push(node);
  }

  #unlink(node: number): void {
    const prev = this.#prev[node];
    const next = this.#next[node];
    this.#next[prev] = next;
    this.#prev[next] = prev;
  }

  #pushFront(node: number): void {
    const first = this.#next[0];
    this.#prev[node] = 0;
    this.#next[node] = first;
    this.#prev[first] = node;
    this.#next[0] = node;
  }
}
