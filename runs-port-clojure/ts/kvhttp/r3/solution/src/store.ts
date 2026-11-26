/** In-memory key-value store. Node runs handlers on a single thread, so no locking is needed. */

export type PutResult = 'created' | 'replaced';

export class Store {
  readonly #entries = new Map<string, Buffer>();

  /** Returns the value stored under `key`, or undefined. */
  fetch(key: string): Buffer | undefined {
    return this.#entries.get(key);
  }

  /** Stores `value` under `key`, reporting whether the key was new. */
  put(key: string, value: Buffer): PutResult {
    const existed = this.#entries.has(key);
    this.#entries.set(key, value);
    return existed ? 'replaced' : 'created';
  }

  /** Removes `key`. Returns true if it was present. */
  delete(key: string): boolean {
    return this.#entries.delete(key);
  }

  /** Returns every key, sorted ascending by UTF-16 code unit. */
  keys(): string[] {
    return [...this.#entries.keys()].sort();
  }
}
