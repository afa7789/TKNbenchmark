/** In-memory key-value store. Node is single-threaded, so no locking is needed. */
export class Store {
  readonly #data = new Map<string, Buffer>();

  /** Stores the value; returns true if the key was new. */
  put(key: string, value: Buffer): boolean {
    const created = !this.#data.has(key);
    this.#data.set(key, value);
    return created;
  }

  get(key: string): Buffer | undefined {
    return this.#data.get(key);
  }

  delete(key: string): boolean {
    return this.#data.delete(key);
  }

  /** All keys, sorted ascending. Keys are ASCII, so code-unit order is byte order. */
  keys(): string[] {
    return [...this.#data.keys()].sort();
  }
}
