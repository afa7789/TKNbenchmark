/** In-memory key-value store whose key listing is always sorted ascending. */
export class KvStore {
  readonly #entries = new Map<string, Buffer>();
  #sortedKeys: string[] | null = null;

  get(key: string): Buffer | undefined {
    return this.#entries.get(key);
  }

  /** Stores `value` under `key`; returns `true` if the key was new. */
  put(key: string, value: Buffer): boolean {
    const created = !this.#entries.has(key);
    this.#entries.set(key, value);
    if (created) this.#sortedKeys = null;
    return created;
  }

  /** Removes `key`; returns `true` if it was present. */
  delete(key: string): boolean {
    const deleted = this.#entries.delete(key);
    if (deleted) this.#sortedKeys = null;
    return deleted;
  }

  /** All keys in ascending order. The returned array must not be mutated. */
  keys(): readonly string[] {
    // Keys are ASCII, so the default UTF-16 code unit ordering is byte order.
    this.#sortedKeys ??= [...this.#entries.keys()].sort();
    return this.#sortedKeys;
  }
}
