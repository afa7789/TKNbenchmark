/** In-memory key-value store. Values are immutable byte buffers. */

export const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export function isValidKey(key: string): boolean {
  return KEY_PATTERN.test(key);
}

export type PutResult = 'created' | 'replaced';

export class Store {
  readonly #entries = new Map<string, Buffer>();

  /** Stores a value; reports whether the key was new or replaced. */
  put(key: string, value: Buffer): PutResult {
    const existed = this.#entries.has(key);
    this.#entries.set(key, value);
    return existed ? 'replaced' : 'created';
  }

  get(key: string): Buffer | undefined {
    return this.#entries.get(key);
  }

  /** Returns true if the key existed and was removed. */
  delete(key: string): boolean {
    return this.#entries.delete(key);
  }

  /** All keys sorted ascending by byte value (keys are ASCII-only). */
  keys(): string[] {
    return [...this.#entries.keys()].sort();
  }
}
