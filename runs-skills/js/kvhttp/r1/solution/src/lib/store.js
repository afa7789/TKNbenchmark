/** In-memory key-value store holding raw bytes. */
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
    return [...this.#data.keys()].sort();
  }
}
