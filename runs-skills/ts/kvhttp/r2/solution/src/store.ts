/** In-memory key-value store holding raw byte values. */
export class KvStore {
  readonly #data = new Map<string, Buffer>();

  /** Stores `value` under `key`; returns true if the key was newly created. */
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

  /** All keys in ascending order. Keys are ASCII, so code-unit order is byte order. */
  keys(): string[] {
    return [...this.#data.keys()].sort();
  }
}
