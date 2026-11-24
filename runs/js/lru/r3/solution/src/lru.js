'use strict'

const NIL = -1

/**
 * Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
 * linked list stored in typed arrays. Every operation is O(1) expected.
 */
class LRUCache {
  constructor(capacity) {
    this.capacity = capacity
    this.index = new Map() // key -> slot
    this.keys = new Array(capacity + 1)
    this.values = new Array(capacity + 1)
    this.prev = new Int32Array(capacity + 1)
    this.next = new Int32Array(capacity + 1)
    this.head = NIL // most recently used
    this.tail = NIL // least recently used
    this.free = [] // recycled slots
    this.nextSlot = 0
  }

  get size() {
    return this.index.size
  }

  get(key) {
    const slot = this.index.get(key)
    if (slot === undefined) return undefined
    this.#moveToFront(slot)
    return this.values[slot]
  }

  set(key, value) {
    let slot = this.index.get(key)
    if (slot !== undefined) {
      this.values[slot] = value
      this.#moveToFront(slot)
      return
    }
    slot = this.free.length > 0 ? this.free.pop() : this.nextSlot++
    this.keys[slot] = key
    this.values[slot] = value
    this.index.set(key, slot)
    this.#pushFront(slot)
    if (this.index.size > this.capacity) this.#removeSlot(this.tail)
  }

  delete(key) {
    const slot = this.index.get(key)
    if (slot === undefined) return false
    this.#removeSlot(slot)
    return true
  }

  #removeSlot(slot) {
    this.#unlink(slot)
    this.index.delete(this.keys[slot])
    this.keys[slot] = undefined
    this.values[slot] = undefined
    this.free.push(slot)
  }

  #pushFront(slot) {
    this.prev[slot] = NIL
    this.next[slot] = this.head
    if (this.head !== NIL) this.prev[this.head] = slot
    else this.tail = slot
    this.head = slot
  }

  #unlink(slot) {
    const p = this.prev[slot]
    const n = this.next[slot]
    if (p !== NIL) this.next[p] = n
    else this.head = n
    if (n !== NIL) this.prev[n] = p
    else this.tail = p
  }

  #moveToFront(slot) {
    if (slot === this.head) return
    this.#unlink(slot)
    this.#pushFront(slot)
  }
}

module.exports = { LRUCache }
