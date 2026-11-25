/** In-memory key-value store holding raw byte values. */
export class KvStore {
  readonly #data = new Map<string, Buffer>();

  get(key: string): Buffer | undefined {
    return this.#data.get(key);
  }

  /** Stores the value; returns true if the key was newly created. */
  put(key: string, value: Buffer): boolean {
    const created = !this.#data.has(key);
    this.#data.set(key, value);
    return created;
  }

  delete(key: string): boolean {
    return this.#data.delete(key);
  }

  keys(): string[] {
    return [...this.#data.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  }
}
