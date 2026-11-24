'use strict'

/**
 * wordfreq: read all of stdin, print the 10 most frequent ASCII words.
 *
 * Words are counted in an open-addressing hash table that references word
 * spans inside the (lower-cased in place) input buffer, so no per-word
 * strings are allocated while scanning.
 */

const TOP_N = 10
const INITIAL_CAPACITY = 1 << 12

/** Lower-case table: maps ASCII letters to lower case, everything else to 0. */
const LOWER = new Uint8Array(256)
for (let c = 0x41; c <= 0x5a; c++) LOWER[c] = c | 0x20
for (let c = 0x61; c <= 0x7a; c++) LOWER[c] = c

class WordTable {
  constructor(buf, capacity = INITIAL_CAPACITY) {
    this.buf = buf
    this.size = 0
    this.#allocate(capacity)
  }

  #allocate(capacity) {
    this.mask = capacity - 1
    this.hashes = new Uint32Array(capacity)
    this.starts = new Int32Array(capacity)
    this.lens = new Int32Array(capacity) // 0 marks an empty slot
    this.counts = new Float64Array(capacity)
  }

  /** Count one occurrence of buf[start, start + len), already lower-cased. */
  add(start, len, hash) {
    const { buf, hashes, starts, lens, mask } = this
    let i = hash & mask
    for (;;) {
      const l = lens[i]
      if (l === 0) break
      if (l === len && hashes[i] === hash && this.#equals(starts[i], start, len)) {
        this.counts[i]++
        return
      }
      i = (i + 1) & mask
    }
    hashes[i] = hash
    starts[i] = start
    lens[i] = len
    this.counts[i] = 1
    if (++this.size * 2 > mask + 1) this.#grow()
  }

  #equals(a, b, len) {
    const buf = this.buf
    for (let k = 0; k < len; k++) if (buf[a + k] !== buf[b + k]) return false
    return true
  }

  #grow() {
    const { hashes, starts, lens, counts } = this
    this.#allocate((this.mask + 1) * 2)
    const mask = this.mask
    for (let j = 0; j < lens.length; j++) {
      if (lens[j] === 0) continue
      let i = hashes[j] & mask
      while (this.lens[i] !== 0) i = (i + 1) & mask
      this.hashes[i] = hashes[j]
      this.starts[i] = starts[j]
      this.lens[i] = lens[j]
      this.counts[i] = counts[j]
    }
  }

  *entries() {
    for (let i = 0; i <= this.mask; i++) {
      if (this.lens[i] !== 0) {
        const s = this.starts[i]
        yield [this.buf.latin1Slice(s, s + this.lens[i]), this.counts[i]]
      }
    }
  }
}

/** Count words in buf. Lower-cases letters in place. */
function countWords(buf) {
  const table = new WordTable(buf)
  const n = buf.length
  let i = 0
  while (i < n) {
    let c = LOWER[buf[i]]
    if (c === 0) {
      i++
      continue
    }
    const start = i
    let hash = 0x811c9dc5 // FNV-1a
    do {
      buf[i] = c
      hash = Math.imul(hash ^ c, 0x01000193)
      c = LOWER[buf[++i]] // out-of-range reads yield undefined -> 0
    } while (c !== 0 && c !== undefined)
    table.add(start, i - start, hash >>> 0)
  }
  return table
}

const byCountThenWord = (a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)

function topWords(table, limit) {
  const top = []
  for (const entry of table.entries()) {
    if (top.length === limit && byCountThenWord(entry, top[limit - 1]) >= 0) continue
    let pos = top.length === limit ? limit - 1 : top.length
    while (pos > 0 && byCountThenWord(entry, top[pos - 1]) < 0) {
      top[pos] = top[pos - 1]
      pos--
    }
    top[pos] = entry
  }
  return top
}

async function readStdin() {
  const chunks = []
  for await (const chunk of process.stdin) chunks.push(chunk)
  return Buffer.concat(chunks)
}

async function main() {
  const input = await readStdin()
  const top = topWords(countWords(input), TOP_N)
  if (top.length > 0) {
    process.stdout.write(top.map(([word, count]) => `${count} ${word}\n`).join(''))
  }
}

main().catch((err) => {
  process.stderr.write(`wordfreq: ${err.message}\n`)
  process.exitCode = 1
})
