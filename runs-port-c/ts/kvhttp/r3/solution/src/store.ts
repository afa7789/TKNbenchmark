/** In-memory key-value store holding raw byte values. */
export class KvStore {
  readonly #entries = new Map<string, Buffer>();

  /** Stores `value` under `key`. Returns true if the key was new. */
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

  /** All keys in ascending code-unit (byte, since keys are ASCII) order. */
  sortedKeys(): string[] {
    return [...this.#entries.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  }
}
