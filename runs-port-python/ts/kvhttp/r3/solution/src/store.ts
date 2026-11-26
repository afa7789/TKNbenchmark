/**
 * In-memory key-value store.
 *
 * Node runs all request handlers on a single thread, so no locking is required.
 */
export class Store {
  readonly #data = new Map<string, Buffer>();

  /** Stores a value; returns true if the key was newly created. */
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

  /** All keys in ascending code-point order. */
  keys(): string[] {
    return [...this.#data.keys()].sort();
  }
}
