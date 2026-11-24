/** In-memory key-value store holding raw byte values. */
export class KvStore {
  readonly #data = new Map<string, Buffer>();

  get(key: string): Buffer | undefined {
    return this.#data.get(key);
  }

  /** Stores `value` under `key`; returns true if the key was newly created. */
  set(key: string, value: Buffer): boolean {
    const created = !this.#data.has(key);
    this.#data.set(key, value);
    return created;
  }

  delete(key: string): boolean {
    return this.#data.delete(key);
  }

  /** All keys sorted ascending by code unit (byte order for valid keys). */
  keys(): string[] {
    return [...this.#data.keys()].sort();
  }
}
