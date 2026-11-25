const NIL = -1;

/**
 * Fixed-capacity LRU cache backed by a Map (key -> slot) and an intrusive
 * doubly linked list stored in typed arrays. Every operation is O(1) expected.
 */
export class LruCache {
  #capacity;
  #index = new Map();
  #keys;
  #values;
  #prev;
  #next;
  #head = NIL; // most recently used
  #tail = NIL; // least recently used
  #free = []; // recycled slots
  #nextSlot = 0;

  /** @param {number} capacity */
  constructor(capacity) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.#capacity = capacity;
    // One spare slot: an insert briefly holds capacity + 1 entries before eviction.
    const slots = capacity + 1;
    this.#keys = new Array(slots);
    this.#values = new Array(slots);
    this.#prev = new Int32Array(slots);
    this.#next = new Int32Array(slots);
  }

  get size() {
    return this.#index.size;
  }

  /** @param {string} key @returns {string | undefined} */
  get(key) {
    const slot = this.#index.get(key);
    if (slot === undefined) return undefined;
    this.#moveToFront(slot);
    return this.#values[slot];
  }

  /** @param {string} key @param {string} value */
  set(key, value) {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      this.#values[existing] = value;
      this.#moveToFront(existing);
      return;
    }
    const slot = this.#free.length > 0 ? this.#free.pop() : this.#nextSlot++;
    this.#keys[slot] = key;
    this.#values[slot] = value;
    this.#index.set(key, slot);
    this.#linkFront(slot);
    if (this.#index.size > this.#capacity) this.#remove(this.#tail);
  }

  /** @param {string} key @returns {boolean} whether the key was present */
  delete(key) {
    const slot = this.#index.get(key);
    if (slot === undefined) return false;
    this.#remove(slot);
    return true;
  }

  #remove(slot) {
    this.#unlink(slot);
    this.#index.delete(this.#keys[slot]);
    this.#keys[slot] = undefined;
    this.#values[slot] = undefined;
    this.#free.push(slot);
  }

  #moveToFront(slot) {
    if (slot === this.#head) return;
    this.#unlink(slot);
    this.#linkFront(slot);
  }

  #linkFront(slot) {
    this.#prev[slot] = NIL;
    this.#next[slot] = this.#head;
    if (this.#head !== NIL) this.#prev[this.#head] = slot;
    else this.#tail = slot;
    this.#head = slot;
  }

  #unlink(slot) {
    const prev = this.#prev[slot];
    const next = this.#next[slot];
    if (prev !== NIL) this.#next[prev] = next;
    else this.#head = next;
    if (next !== NIL) this.#prev[next] = prev;
    else this.#tail = prev;
  }
}
