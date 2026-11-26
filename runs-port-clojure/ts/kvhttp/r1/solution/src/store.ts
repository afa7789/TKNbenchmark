/** In-memory key-value store. */
export class Store {
  readonly #entries = new Map<string, Buffer>();

  /** Stores `value` under `key`. Returns true if the key was new. */
  put(key: string, value: Buffer): boolean {
    const isNew = !this.#entries.has(key);
    this.#entries.set(key, value);
    return isNew;
  }

  /** Returns the value stored under `key`, or undefined. */
  lookup(key: string): Buffer | undefined {
    return this.#entries.get(key);
  }

  /** Removes `key`. Returns true if it was present. */
  delete(key: string): boolean {
    return this.#entries.delete(key);
  }

  /** Returns every key in ascending order. */
  keys(): string[] {
    // Keys are ASCII, so code-unit order is byte order.
    return [...this.#entries.keys()].sort();
  }
}
