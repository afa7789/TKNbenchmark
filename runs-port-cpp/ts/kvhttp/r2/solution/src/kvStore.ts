export type PutResult = 'created' | 'replaced';

/** In-memory key-value store holding raw byte values. */
export class KvStore {
  readonly #data = new Map<string, Buffer>();

  put(key: string, value: Buffer): PutResult {
    const existed = this.#data.has(key);
    this.#data.set(key, value);
    return existed ? 'replaced' : 'created';
  }

  get(key: string): Buffer | undefined {
    return this.#data.get(key);
  }

  delete(key: string): boolean {
    return this.#data.delete(key);
  }

  /** All keys, sorted ascending by byte value (keys are ASCII). */
  keys(): string[] {
    return [...this.#data.keys()].sort();
  }
}
