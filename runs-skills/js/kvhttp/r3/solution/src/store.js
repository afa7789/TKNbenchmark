/** In-memory key-value store holding raw byte values. */
export class Store {
  #data = new Map();

  get(key) {
    return this.#data.get(key);
  }

  /** Stores a value; returns true if the key was newly created. */
  set(key, value) {
    const created = !this.#data.has(key);
    this.#data.set(key, value);
    return created;
  }

  delete(key) {
    return this.#data.delete(key);
  }

  /** All keys sorted ascending by code unit (keys are ASCII). */
  keys() {
    return [...this.#data.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  }
}
