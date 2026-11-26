const NIL = -1

/**
 * Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
 * linked list stored in typed arrays. Every operation is O(1) expected.
 */
export class LRUCache<K, V> {
  readonly capacity: number

  readonly #index = new Map<K, number>() // key -> slot
  readonly #keys: (K | undefined)[]
  readonly #values: (V | undefined)[]
  readonly #prev: Int32Array
  readonly #next: Int32Array
  readonly #free: number[] = [] // recycled slots
  #head = NIL // most recently used
  #tail = NIL // least recently used
  #nextSlot = 0

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`)
    }
    this.capacity = capacity
    // One spare slot: a new entry is linked before the LRU one is evicted.
    const slots = capacity + 1
    this.#keys = new Array<K | undefined>(slots)
    this.#values = new Array<V | undefined>(slots)
    this.#prev = new Int32Array(slots)
    this.#next = new Int32Array(slots)
  }

  get size(): number {
    return this.#index.size
  }

  /** Returns the value for `key` and marks it most recently used. */
  get(key: K): V | undefined {
    const slot = this.#index.get(key)
    if (slot === undefined) return undefined
    this.#moveToFront(slot)
    return this.#values[slot]
  }

  /** Inserts or overwrites `key`, evicting the least recently used entry if over capacity. */
  set(key: K, value: V): void {
    const existing = this.#index.get(key)
    if (existing !== undefined) {
      this.#values[existing] = value
      this.#moveToFront(existing)
      return
    }
    const slot = this.#free.pop() ?? this.#nextSlot++
    this.#keys[slot] = key
    this.#values[slot] = value
    this.#index.set(key, slot)
    this.#pushFront(slot)
    if (this.#index.size > this.capacity) this.#removeSlot(this.#tail)
  }

  /** Removes `key`; returns whether it was present. */
  delete(key: K): boolean {
    const slot = this.#index.get(key)
    if (slot === undefined) return false
    this.#removeSlot(slot)
    return true
  }

  #removeSlot(slot: number): void {
    this.#unlink(slot)
    this.#index.delete(this.#keys[slot] as K)
    this.#keys[slot] = undefined
    this.#values[slot] = undefined
    this.#free.push(slot)
  }

  #pushFront(slot: number): void {
    this.#prev[slot] = NIL
    this.#next[slot] = this.#head
    if (this.#head !== NIL) this.#prev[this.#head] = slot
    else this.#tail = slot
    this.#head = slot
  }

  #unlink(slot: number): void {
    const p = this.#prev[slot]!
    const n = this.#next[slot]!
    if (p !== NIL) this.#next[p] = n
    else this.#head = n
    if (n !== NIL) this.#prev[n] = p
    else this.#tail = p
  }

  #moveToFront(slot: number): void {
    if (slot === this.#head) return
    this.#unlink(slot)
    this.#pushFront(slot)
  }
}
