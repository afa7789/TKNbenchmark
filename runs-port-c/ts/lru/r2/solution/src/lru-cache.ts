/**
 * A fixed-capacity least-recently-used cache.
 *
 * A `Map` indexes the entries, which are linked into a circular doubly linked
 * recency list around a sentinel: `sentinel.next` is the most recently used,
 * `sentinel.prev` the least. Every operation runs in O(1) expected time.
 *
 * (Relying on `Map` insertion order for recency is tempting but not O(1) in
 * V8: finding the first live key skips over every deleted slot before it.)
 */
interface Node<K, V> {
  key: K;
  value: V;
  prev: Node<K, V>;
  next: Node<K, V>;
}

export class LruCache<K, V> {
  readonly #capacity: number;
  readonly #index = new Map<K, Node<K, V>>();
  readonly #sentinel: Node<K, V>;

  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new RangeError(`capacity must be a positive integer, got ${capacity}`);
    }
    this.#capacity = capacity;
    const sentinel = { prev: undefined, next: undefined } as unknown as Node<K, V>;
    sentinel.prev = sentinel;
    sentinel.next = sentinel;
    this.#sentinel = sentinel;
  }

  get size(): number {
    return this.#index.size;
  }

  /** Inserts or overwrites `key`, making it the most recently used. */
  set(key: K, value: V): void {
    const existing = this.#index.get(key);
    if (existing !== undefined) {
      existing.value = value;
      this.#touch(existing);
      return;
    }

    let node: Node<K, V>;
    if (this.#index.size >= this.#capacity) {
      // Full: recycle the least recently used node for the new entry.
      node = this.#sentinel.prev;
      this.#index.delete(node.key);
      node.key = key;
      node.value = value;
      this.#touch(node);
    } else {
      const head = this.#sentinel.next;
      node = { key, value, prev: this.#sentinel, next: head };
      head.prev = node;
      this.#sentinel.next = node;
    }
    this.#index.set(key, node);
  }

  /** Returns the value for `key` (making it the most recently used), or `undefined`. */
  get(key: K): V | undefined {
    const node = this.#index.get(key);
    if (node === undefined) return undefined;
    this.#touch(node);
    return node.value;
  }

  /** Removes `key`; returns whether it was present. */
  delete(key: K): boolean {
    const node = this.#index.get(key);
    if (node === undefined) return false;
    this.#index.delete(key);
    LruCache.#unlink(node);
    return true;
  }

  /** Moves a linked node to the most recently used position. */
  #touch(node: Node<K, V>): void {
    const sentinel = this.#sentinel;
    if (sentinel.next === node) return;
    LruCache.#unlink(node);
    const head = sentinel.next;
    node.prev = sentinel;
    node.next = head;
    head.prev = node;
    sentinel.next = node;
  }

  static #unlink<K, V>(node: Node<K, V>): void {
    node.prev.next = node.next;
    node.next.prev = node.prev;
  }
}
