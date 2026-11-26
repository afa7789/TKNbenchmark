/** In-memory key/value store. Node runs request handlers on a single thread, so no locking is needed. */
export class Store {
  readonly #data = new Map<string, Buffer>();

  /** Returns true if the key was newly created, false if it replaced a value. */
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

  /** Keys in ascending order. Keys are ASCII, so code-unit order equals byte order. */
  keys(): string[] {
    return [...this.#data.keys()].sort();
  }
}
