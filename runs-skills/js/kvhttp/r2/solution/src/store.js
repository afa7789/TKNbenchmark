/** In-memory key-value store holding raw byte values. */
export class Store {
  #data = new Map();

  /** @returns {boolean} true if the key was newly created */
  set(key, value) {
    const created = !this.#data.has(key);
    this.#data.set(key, value);
    return created;
  }

  get(key) {
    return this.#data.get(key);
  }

  delete(key) {
    return this.#data.delete(key);
  }

  keys() {
    // Keys are ASCII, so code-unit ordering is byte ordering.
    return [...this.#data.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  }
}
