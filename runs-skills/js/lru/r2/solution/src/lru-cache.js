const HEAD = 0;

/**
 * Fixed-capacity least-recently-used cache.
 *
 * A Map indexes keys to slots; slots form a circular doubly linked list
 * (stored in typed arrays) ordered from most to least recently used, with
 * slot 0 as the sentinel. Every operation is O(1) expected time.
 *
 * Map iteration order is deliberately not used for eviction: after many
 * deletions V8 must skip the leading holes on each `keys().next()`, which
 * degrades eviction far beyond O(1).
 */
export class LruCache {
  #capacity;
  #index = new Map();
  #keys;
  #values;
  #prev;
  #next;
  /** Slots that have never been used start at #fresh; freed slots are chained through #next. */
  #fresh = 1;
  #free = HEAD;

  /** @param {number} capacity maximum number of keys held (>= 1) */
  constructor(capacity) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.#capacity = capacity;
    // One spare slot lets SET insert before evicting.
    const slots = capacity + 2;
    this.#keys = new Array(slots).fill(undefined);
    this.#values = new Array(slots).fill(undefined);
    this.#prev = new Int32Array(slots);
    this.#next = new Int32Array(slots);
  }

  get size() {
    return this.#index.size;
  }

  /** @returns {string | undefined} */
  get(key) {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#unlink(slot);
    this.#pushFront(slot);
    return this.#values[slot];
  }

  set(key, value) {
    const index = this.#index;
    let slot = index.get(key);
    if (slot !== undefined) {
      this.#unlink(slot);
    } else {
      slot = this.#allocate();
      this.#keys[slot] = key;
      index.set(key, slot);
    }
    this.#values[slot] = value;
    this.#pushFront(slot);
    if (index.size > this.#capacity) this.#remove(this.#prev[HEAD]);
  }

  /** @returns {boolean} whether the key was present */
  delete(key) {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #allocate() {
    if (this.#free !== HEAD) {
      const slot = this.#free;
      this.#free = this.#next[slot];
      return slot;
    }
    return this.#fresh++;
  }

  #remove(slot) {
    this.#unlink(slot);
    this.#index.delete(this.#keys[slot]);
    this.#keys[slot] = undefined;
    this.#values[slot] = undefined;
    this.#next[slot] = this.#free;
    this.#free = slot;
  }

  #unlink(slot) {
    const prev = this.#prev;
    const next = this.#next;
    const before = prev[slot];
    const after = next[slot];
    next[before] = after;
    prev[after] = before;
  }

  #pushFront(slot) {
    const prev = this.#prev;
    const next = this.#next;
    const first = next[HEAD];
    prev[slot] = HEAD;
    next[slot] = first;
    prev[first] = slot;
    next[HEAD] = slot;
  }
}
