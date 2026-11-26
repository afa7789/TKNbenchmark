/** In-memory key-value store. Node's event loop serialises access, so no locking is needed. */
export class KvStore {
  readonly #entries = new Map<string, Buffer>();

  /** Stores `value` under `key`; returns `true` if the key was new, `false` if a value was replaced. */
  put(key: string, value: Buffer): boolean {
    const isNew = !this.#entries.has(key);
    this.#entries.set(key, value);
    return isNew;
  }

  get(key: string): Buffer | undefined {
    return this.#entries.get(key);
  }

  /** Returns `true` if the key was present and has been removed. */
  delete(key: string): boolean {
    return this.#entries.delete(key);
  }

  /** Returns a snapshot of all keys in ascending order. */
  keys(): string[] {
    // Keys are ASCII-only, so code-unit ordering is byte ordering.
    return [...this.#entries.keys()].sort();
  }
}
