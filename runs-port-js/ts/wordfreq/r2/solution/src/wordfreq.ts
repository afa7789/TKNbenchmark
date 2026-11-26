/**
 * wordfreq: read all of stdin, print the 10 most frequent ASCII words.
 *
 * Words are counted in an open-addressing hash table that references word
 * spans inside the (lower-cased in place) input buffer, so no per-word
 * strings are allocated while scanning.
 */

import { Buffer } from 'node:buffer'
import process from 'node:process'

const TOP_N = 10
const INITIAL_CAPACITY = 1 << 12

const FNV_OFFSET_BASIS = 0x811c9dc5
const FNV_PRIME = 0x01000193

/** Lower-case table: maps ASCII letters to lower case, everything else to 0. */
const LOWER: Uint8Array = (() => {
  const table = new Uint8Array(256)
  for (let c = 0x41; c <= 0x5a; c++) table[c] = c | 0x20
  for (let c = 0x61; c <= 0x7a; c++) table[c] = c
  return table
})()

/** A counted word: the lower-cased word and its number of occurrences. */
type WordCount = readonly [word: string, count: number]

/**
 * Hash table from word spans in a shared buffer to occurrence counts.
 * Uses linear probing over parallel typed arrays; a length of 0 marks an
 * empty slot (words are never empty).
 */
class WordTable {
  readonly #buf: Uint8Array
  #size = 0
  #mask = 0
  #hashes = new Uint32Array(0)
  #starts = new Int32Array(0)
  #lens = new Int32Array(0)
  #counts = new Uint32Array(0)

  constructor(buf: Uint8Array, capacity: number = INITIAL_CAPACITY) {
    if (capacity <= 0 || (capacity & (capacity - 1)) !== 0) {
      throw new RangeError(`capacity must be a positive power of two, got ${capacity}`)
    }
    this.#buf = buf
    this.#allocate(capacity)
  }

  get size(): number {
    return this.#size
  }

  #allocate(capacity: number): void {
    this.#mask = capacity - 1
    this.#hashes = new Uint32Array(capacity)
    this.#starts = new Int32Array(capacity)
    this.#lens = new Int32Array(capacity)
    this.#counts = new Uint32Array(capacity)
  }

  /** Count one occurrence of buf[start, start + len), already lower-cased. */
  add(start: number, len: number, hash: number): void {
    const hashes = this.#hashes
    const starts = this.#starts
    const lens = this.#lens
    const mask = this.#mask
    let i = hash & mask
    for (;;) {
      const l = lens[i]!
      if (l === 0) break
      if (l === len && hashes[i] === hash && this.#equals(starts[i]!, start, len)) {
        this.#counts[i]!++
        return
      }
      i = (i + 1) & mask
    }
    hashes[i] = hash
    starts[i] = start
    lens[i] = len
    this.#counts[i] = 1
    if (++this.#size * 2 > mask + 1) this.#grow()
  }

  #equals(a: number, b: number, len: number): boolean {
    const buf = this.#buf
    for (let k = 0; k < len; k++) {
      if (buf[a + k] !== buf[b + k]) return false
    }
    return true
  }

  #grow(): void {
    const hashes = this.#hashes
    const starts = this.#starts
    const lens = this.#lens
    const counts = this.#counts
    this.#allocate((this.#mask + 1) * 2)
    const mask = this.#mask
    for (let j = 0; j < lens.length; j++) {
      const len = lens[j]!
      if (len === 0) continue
      const hash = hashes[j]!
      let i = hash & mask
      while (this.#lens[i] !== 0) i = (i + 1) & mask
      this.#hashes[i] = hash
      this.#starts[i] = starts[j]!
      this.#lens[i] = len
      this.#counts[i] = counts[j]!
    }
  }

  *entries(): Generator<WordCount> {
    const buf = this.#buf
    for (let i = 0; i <= this.#mask; i++) {
      const len = this.#lens[i]!
      if (len === 0) continue
      const start = this.#starts[i]!
      yield [Buffer.from(buf.buffer, buf.byteOffset + start, len).toString('latin1'), this.#counts[i]!]
    }
  }
}

/** Count words in buf. Lower-cases letters in place. */
function countWords(buf: Uint8Array): WordTable {
  const table = new WordTable(buf)
  const n = buf.length
  let i = 0
  while (i < n) {
    let c = LOWER[buf[i]!]!
    if (c === 0) {
      i++
      continue
    }
    const start = i
    let hash = FNV_OFFSET_BASIS // FNV-1a
    do {
      buf[i] = c
      hash = Math.imul(hash ^ c, FNV_PRIME)
      i++
      c = i < n ? LOWER[buf[i]!]! : 0
    } while (c !== 0)
    table.add(start, i - start, hash >>> 0)
  }
  return table
}

/** Orders by count descending, then word ascending (byte order). */
function byCountThenWord(a: WordCount, b: WordCount): number {
  if (a[1] !== b[1]) return b[1] - a[1]
  return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0
}

/** Selects the `limit` best entries without sorting the whole table. */
function topWords(entries: Iterable<WordCount>, limit: number): WordCount[] {
  const top: WordCount[] = []
  if (limit <= 0) return top
  for (const entry of entries) {
    const full = top.length === limit
    if (full && byCountThenWord(entry, top[limit - 1]!) >= 0) continue
    let pos = full ? limit - 1 : top.length
    while (pos > 0 && byCountThenWord(entry, top[pos - 1]!) < 0) {
      top[pos] = top[pos - 1]!
      pos--
    }
    top[pos] = entry
  }
  return top
}

async function readStdin(): Promise<Buffer> {
  const chunks: Buffer[] = []
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer)
  return Buffer.concat(chunks)
}

async function main(): Promise<void> {
  const input = await readStdin()
  const top = topWords(countWords(input).entries(), TOP_N)
  if (top.length > 0) {
    process.stdout.write(top.map(([word, count]) => `${count} ${word}\n`).join(''))
  }
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.message : String(err)
  process.stderr.write(`wordfreq: ${message}\n`)
  process.exitCode = 1
})
