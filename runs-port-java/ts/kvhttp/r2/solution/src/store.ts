/** In-memory store whose key listing is returned in ascending order. */
export class KvStore {
  readonly #entries = new Map<string, Buffer>();
  #sortedKeys: string[] | null = [];

  /** Stores the value; returns `true` if the key was newly created. */
  put(key: string, value: Buffer): boolean {
    const created = !this.#entries.has(key);
    this.#entries.set(key, value);
    if (created) this.#sortedKeys = null;
    return created;
  }

  get(key: string): Buffer | undefined {
    return this.#entries.get(key);
  }

  /** Removes the key; returns `true` if it was present. */
  delete(key: string): boolean {
    const deleted = this.#entries.delete(key);
    if (deleted) this.#sortedKeys = null;
    return deleted;
  }

  /** All keys in ascending code-unit order (keys are ASCII, so this equals byte order). */
  keys(): readonly string[] {
    this.#sortedKeys ??= [...this.#entries.keys()].sort();
    return this.#sortedKeys;
  }
}
