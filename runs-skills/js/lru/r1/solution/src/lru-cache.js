const NIL = -1;

/**
 * Fixed-capacity LRU cache with O(1) get/set/delete.
 *
 * Entries live in preallocated slots linked into a doubly-linked recency list
 * (head = least recently used, tail = most recently used); a Map indexes keys
 * to slots. Freed slots are recycled through a free list.
 */
export class LRUCache {
  #capacity;
  #index = new Map();
  #keys;
  #values;
  #prev;
  #next;
  #head = NIL;
  #tail = NIL;
  #free = NIL;
  #used = 0;

  /** @param {number} capacity maximum number of keys held (>= 1) */
  constructor(capacity) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.#capacity = capacity;
    this.#keys = new Array(capacity);
    this.#values = new Array(capacity);
    this.#prev = new Int32Array(capacity);
    this.#next = new Int32Array(capacity);
  }

  get size() {
    return this.#index.size;
  }

  /** @returns {string | undefined} */
  get(key) {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#touch(slot);
    return this.#values[slot];
  }

  set(key, value) {
    let slot = this.#index.get(key);
    if (slot !== undefined) {
      this.#values[slot] = value;
      this.#touch(slot);
      return;
    }
    if (this.#index.size === this.#capacity) this.#evict();
    slot = this.#allocate();
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#append(slot);
  }

  /** @returns {boolean} whether the key was present */
  delete(key) {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#index.delete(key);
    this.#unlink(slot);
    this.#release(slot);
    return true;
  }

  #evict() {
    const slot = this.#head;
    this.#index.delete(this.#keys[slot]);
    this.#unlink(slot);
    this.#release(slot);
  }

  #allocate() {
    if (this.#free !== NIL) {
      const slot = this.#free;
      this.#free = this.#next[slot];
      return slot;
    }
    return this.#used++;
  }

  #release(slot) {
    this.#keys[slot] = undefined;
    this.#values[slot] = undefined;
    this.#next[slot] = this.#free;
    this.#free = slot;
  }

  #touch(slot) {
    if (slot === this.#tail) return;
    this.#unlink(slot);
    this.#append(slot);
  }

  #append(slot) {
    this.#prev[slot] = this.#tail;
    this.#next[slot] = NIL;
    if (this.#tail === NIL) this.#head = slot;
    else this.#next[this.#tail] = slot;
    this.#tail = slot;
  }

  #unlink(slot) {
    const prev = this.#prev[slot];
    const next = this.#next[slot];
    if (prev === NIL) this.#head = next;
    else this.#next[prev] = next;
    if (next === NIL) this.#tail = prev;
    else this.#prev[next] = prev;
  }
}
