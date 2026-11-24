/** In-memory key-value store. Values are kept as raw bytes. */
export class KvStore {
  readonly #entries = new Map<string, Buffer>();

  /** Stores `value` under `key`; returns true if the key was newly created. */
  set(key: string, value: Buffer): boolean {
    const created = !this.#entries.has(key);
    this.#entries.set(key, value);
    return created;
  }

  get(key: string): Buffer | undefined {
    return this.#entries.get(key);
  }

  delete(key: string): boolean {
    return this.#entries.delete(key);
  }

  /** All keys in ascending (code-unit) order. */
  keys(): string[] {
    return [...this.#entries.keys()].sort();
  }
}
