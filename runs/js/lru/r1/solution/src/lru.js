'use strict';

const NIL = -1;

/**
 * Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
 * linked list stored in typed arrays. All operations are O(1) expected.
 */
class LRUCache {
  constructor(capacity) {
    this.capacity = capacity;
    this.index = new Map();          // key -> slot
    this.keys = new Array(capacity);
    this.values = new Array(capacity);
    this.prev = new Int32Array(capacity);
    this.next = new Int32Array(capacity);
    this.head = NIL;                 // most recently used
    this.tail = NIL;                 // least recently used
    this.freeList = [];
    this.nextUnused = 0;
  }

  get size() {
    return this.index.size;
  }

  get(key) {
    const slot = this.index.get(key);
    if (slot === undefined) return undefined;
    this.#moveToFront(slot);
    return this.values[slot];
  }

  set(key, value) {
    let slot = this.index.get(key);
    if (slot !== undefined) {
      this.values[slot] = value;
      this.#moveToFront(slot);
      return;
    }
    if (this.index.size >= this.capacity) this.#evict();
    slot = this.freeList.length > 0 ? this.freeList.pop() : this.nextUnused++;
    this.keys[slot] = key;
    this.values[slot] = value;
    this.index.set(key, slot);
    this.#pushFront(slot);
  }

  delete(key) {
    const slot = this.index.get(key);
    if (slot === undefined) return false;
    this.#release(slot);
    return true;
  }

  #evict() {
    this.#release(this.tail);
  }

  #release(slot) {
    this.#unlink(slot);
    this.index.delete(this.keys[slot]);
    this.keys[slot] = undefined;
    this.values[slot] = undefined;
    this.freeList.push(slot);
  }

  #unlink(slot) {
    const p = this.prev[slot];
    const n = this.next[slot];
    if (p === NIL) this.head = n; else this.next[p] = n;
    if (n === NIL) this.tail = p; else this.prev[n] = p;
  }

  #pushFront(slot) {
    this.prev[slot] = NIL;
    this.next[slot] = this.head;
    if (this.head === NIL) this.tail = slot; else this.prev[this.head] = slot;
    this.head = slot;
  }

  #moveToFront(slot) {
    if (slot === this.head) return;
    this.#unlink(slot);
    this.#pushFront(slot);
  }
}

module.exports = { LRUCache };
