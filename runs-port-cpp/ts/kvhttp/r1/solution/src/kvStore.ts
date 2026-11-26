/** In-memory key/value store. Values are stored as immutable byte buffers. */
export class KvStore {
  readonly #map = new Map<string, Buffer>();

  /** Stores `value` under `key`. Returns true if the key was new, false if it replaced a value. */
  put(key: string, value: Buffer): boolean {
    const created = !this.#map.has(key);
    this.#map.set(key, value);
    return created;
  }

  get(key: string): Buffer | undefined {
    return this.#map.get(key);
  }

  /** Removes `key`. Returns true if it was present. */
  delete(key: string): boolean {
    return this.#map.delete(key);
  }

  /** All keys in ascending byte-wise order. */
  keys(): string[] {
    // Keys are ASCII, so UTF-16 code-unit order equals byte order.
    return [...this.#map.keys()].sort();
  }
}
