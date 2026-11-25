// Counts ASCII-letter words in byte input using an open-addressing hash table
// whose keys live in a shared byte arena, avoiding a string allocation per word.

const INITIAL_SLOTS = 1 << 14;
const MAX_LOAD = 0.5;
const FNV_OFFSET = 0x811c9dc5;
const FNV_PRIME = 0x01000193;

/** Lowercase table: 0 for separators, otherwise the lowercased ASCII letter. */
const LOWER = new Uint8Array(256);
for (let c = 0x41; c <= 0x5a; c++) LOWER[c] = c | 0x20;
for (let c = 0x61; c <= 0x7a; c++) LOWER[c] = c;

export class WordCounter {
  #slots = new Int32Array(INITIAL_SLOTS).fill(-1);
  #mask = INITIAL_SLOTS - 1;
  #size = 0;
  #starts = new Int32Array(1024);
  #lengths = new Int32Array(1024);
  #hashes = new Int32Array(1024);
  #counts = new Float64Array(1024);
  #arena = new Uint8Array(1 << 16);
  #arenaUsed = 0;
  // Pending word that may continue into the next chunk.
  #word = new Uint8Array(64);
  #wordLen = 0;

  /** Feed a chunk of bytes; words may span chunk boundaries. */
  add(bytes) {
    let word = this.#word;
    let len = this.#wordLen;
    for (let i = 0, n = bytes.length; i < n; i++) {
      const c = LOWER[bytes[i]];
      if (c !== 0) {
        if (len === word.length) {
          const grown = new Uint8Array(len * 2);
          grown.set(word);
          this.#word = word = grown;
        }
        word[len++] = c;
      } else if (len !== 0) {
        this.#record(word, len);
        len = 0;
      }
    }
    this.#wordLen = len;
  }

  /** Flush any trailing word. */
  finish() {
    if (this.#wordLen !== 0) {
      this.#record(this.#word, this.#wordLen);
      this.#wordLen = 0;
    }
  }

  /** Top `limit` words by count desc, then word ascending (byte order). */
  top(limit) {
    const entries = [];
    for (let e = 0; e < this.#size; e++) {
      const start = this.#starts[e];
      entries.push({
        word: Buffer.from(this.#arena.buffer, start, this.#lengths[e]).toString('latin1'),
        count: this.#counts[e],
      });
    }
    // Words are pure ASCII, so string comparison equals byte order.
    entries.sort((a, b) => b.count - a.count || (a.word < b.word ? -1 : a.word > b.word ? 1 : 0));
    return entries.slice(0, limit);
  }

  #record(word, len) {
    let h = FNV_OFFSET;
    for (let i = 0; i < len; i++) h = Math.imul(h ^ word[i], FNV_PRIME);

    const slots = this.#slots;
    const mask = this.#mask;
    let s = h & mask;
    for (;;) {
      const e = slots[s];
      if (e === -1) break;
      if (this.#hashes[e] === h && this.#lengths[e] === len && this.#matches(e, word, len)) {
        this.#counts[e]++;
        return;
      }
      s = (s + 1) & mask;
    }

    const e = this.#insertEntry(word, len, h);
    slots[s] = e;
    if (this.#size > (mask + 1) * MAX_LOAD) this.#rehash();
  }

  #matches(e, word, len) {
    const arena = this.#arena;
    const start = this.#starts[e];
    for (let i = 0; i < len; i++) if (arena[start + i] !== word[i]) return false;
    return true;
  }

  #insertEntry(word, len, h) {
    const e = this.#size++;
    if (e === this.#starts.length) {
      const cap = e * 2;
      this.#starts = grow(Int32Array, this.#starts, cap);
      this.#lengths = grow(Int32Array, this.#lengths, cap);
      this.#hashes = grow(Int32Array, this.#hashes, cap);
      this.#counts = grow(Float64Array, this.#counts, cap);
    }
    if (this.#arenaUsed + len > this.#arena.length) {
      this.#arena = grow(Uint8Array, this.#arena, Math.max(this.#arena.length * 2, this.#arenaUsed + len));
    }
    this.#arena.set(word.subarray(0, len), this.#arenaUsed);
    this.#starts[e] = this.#arenaUsed;
    this.#lengths[e] = len;
    this.#hashes[e] = h;
    this.#counts[e] = 1;
    this.#arenaUsed += len;
    return e;
  }

  #rehash() {
    const capacity = this.#slots.length * 2;
    const slots = new Int32Array(capacity).fill(-1);
    const mask = capacity - 1;
    for (let e = 0; e < this.#size; e++) {
      let s = this.#hashes[e] & mask;
      while (slots[s] !== -1) s = (s + 1) & mask;
      slots[s] = e;
    }
    this.#slots = slots;
    this.#mask = mask;
  }
}

function grow(Type, array, capacity) {
  const next = new Type(capacity);
  next.set(array);
  return next;
}
