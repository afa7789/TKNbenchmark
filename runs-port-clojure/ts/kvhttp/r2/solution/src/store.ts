/**
 * In-memory key-value store. Node runs request handlers on a single thread,
 * so plain Map operations are atomic with respect to concurrent requests.
 */

export type PutResult = 'created' | 'replaced';

export class Store {
  readonly #entries = new Map<string, Uint8Array>();

  /** Stores `value` under `key`, reporting whether the key was new. */
  put(key: string, value: Uint8Array): PutResult {
    const existed = this.#entries.has(key);
    this.#entries.set(key, value);
    return existed ? 'replaced' : 'created';
  }

  /** Returns the value stored under `key`, or `undefined`. */
  get(key: string): Uint8Array | undefined {
    return this.#entries.get(key);
  }

  /** Removes `key`. Returns true if it was present. */
  delete(key: string): boolean {
    return this.#entries.delete(key);
  }

  /** Returns all keys in ascending (code unit) order. */
  keys(): string[] {
    return [...this.#entries.keys()].sort();
  }
}
