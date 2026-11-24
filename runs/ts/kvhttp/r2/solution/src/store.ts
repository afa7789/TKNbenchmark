/** In-memory key-value store holding raw byte values. */
export class KvStore {
  readonly #data = new Map<string, Buffer>();

  /** Stores a value; returns true if the key was newly created. */
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

  /** All keys sorted ascending by code unit (keys are ASCII). */
  keys(): string[] {
    return [...this.#data.keys()].sort();
  }
}
