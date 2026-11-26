/** In-memory key-value store. Keys are strings, values are raw bytes. */
export class KvStore {
  readonly #entries = new Map<string, Buffer>();

  /** Stores `value` under `key`. Returns true if the key was newly created. */
  put(key: string, value: Buffer): boolean {
    const created = !this.#entries.has(key);
    this.#entries.set(key, value);
    return created;
  }

  get(key: string): Buffer | undefined {
    return this.#entries.get(key);
  }

  /** Returns true if the key existed and was removed. */
  delete(key: string): boolean {
    return this.#entries.delete(key);
  }

  /** All keys, sorted ascending by code unit (byte order for ASCII keys). */
  keys(): string[] {
    return [...this.#entries.keys()].sort();
  }
}
