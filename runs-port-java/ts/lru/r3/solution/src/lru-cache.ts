/**
 * A fixed-capacity cache that evicts the least recently used entry.
 *
 * Entries live in a doubly linked list stored in preallocated typed arrays
 * (indexed by slot), with a Map from key to slot. Every operation runs in
 * O(1) expected time and no per-entry objects are allocated.
 */
export class LruCache<V> {
  readonly #capacity: number;
  readonly #slots = new Map<string, number>();
  readonly #keys: string[];
  readonly #values: (V | undefined)[];
  readonly #prev: Int32Array;
  readonly #next: Int32Array;
  /** Most recently used slot, or -1 when empty. */
  #head = -1;
  /** Least recently used slot, or -1 when empty. */
  #tail = -1;
  /** Slots released by deletion, available for reuse. */
  readonly #free: number[] = [];
  /** Number of slots ever handed out. */
  #allocated = 0;

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer: ${capacity}`);
    }
    this.#capacity = capacity;
    // One extra slot: an insert happens before the eviction it may trigger.
    const slotCount = capacity + 1;
    this.#keys = new Array<string>(slotCount);
    this.#values = new Array<V | undefined>(slotCount);
    this.#prev = new Int32Array(slotCount);
    this.#next = new Int32Array(slotCount);
  }

  get size(): number {
    return this.#slots.size;
  }

  /** Inserts or overwrites a mapping, marking the key as most recently used. */
  set(key: string, value: V): void {
    const existing = this.#slots.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#moveToFront(existing);
      return;
    }
    const slot = this.#free.length > 0 ? this.#free.pop()! : this.#allocated++;
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#slots.set(key, slot);
    this.#linkFront(slot);
    if (this.#slots.size > this.#capacity) {
      this.#remove(this.#tail);
    }
  }

  /** Returns the value for the key (marking it most recently used), or `undefined`. */
  get(key: string): V | undefined {
    const slot = this.#slots.get(key);
    if (slot === undefined) return undefined;
    this.#moveToFront(slot);
    return this.#values[slot];
  }

  /** Removes the key; returns whether it was present. */
  delete(key: string): boolean {
    const slot = this.#slots.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #remove(slot: number): void {
    this.#unlink(slot);
    this.#slots.delete(this.#keys[slot]!);
    this.#keys[slot] = '';
    this.#values[slot] = undefined;
    this.#free.push(slot);
  }

  #moveToFront(slot: number): void {
    if (slot === this.#head) return;
    this.#unlink(slot);
    this.#linkFront(slot);
  }

  #linkFront(slot: number): void {
    this.#prev[slot] = -1;
    this.#next[slot] = this.#head;
    if (this.#head !== -1) this.#prev[this.#head] = slot;
    else this.#tail = slot;
    this.#head = slot;
  }

  #unlink(slot: number): void {
    const before = this.#prev[slot]!;
    const after = this.#next[slot]!;
    if (before !== -1) this.#next[before] = after;
    else this.#head = after;
    if (after !== -1) this.#prev[after] = before;
    else this.#tail = before;
  }
}
