// LRU cache simulator: reads a capacity and a stream of commands from stdin,
// writes command results to stdout. See SPEC.md.
import { readSync, writeSync } from 'node:fs'

const NIL = -1

/** Fixed-capacity LRU cache backed by a hash index and an array-based doubly linked list. */
export class LruCache {
  readonly #capacity: number
  readonly #index = new Map<string, number>()
  readonly #keys: string[] = []
  readonly #values: string[] = []
  #prev: Int32Array
  #next: Int32Array
  #head = NIL // least recently used
  #tail = NIL // most recently used
  #free = NIL // singly linked free list through #next
  #allocated = 0

  constructor(capacity: number) {
    this.#capacity = capacity
    const initial = Math.min(capacity + 1, 1 << 16)
    this.#prev = new Int32Array(initial)
    this.#next = new Int32Array(initial)
  }

  get size(): number {
    return this.#index.size
  }

  get(key: string): string | undefined {
    const slot = this.#index.get(key)
    if (slot === undefined) return undefined
    this.#moveToTail(slot)
    return this.#values[slot]
  }

  set(key: string, value: string): void {
    const existing = this.#index.get(key)
    if (existing !== undefined) {
      this.#values[existing] = value
      this.#moveToTail(existing)
      return
    }
    const slot = this.#allocate()
    this.#keys[slot] = key
    this.#values[slot] = value
    this.#index.set(key, slot)
    this.#linkTail(slot)
    if (this.#index.size > this.#capacity) this.#remove(this.#head)
  }

  delete(key: string): boolean {
    const slot = this.#index.get(key)
    if (slot === undefined) return false
    this.#remove(slot)
    return true
  }

  #allocate(): number {
    if (this.#free !== NIL) {
      const slot = this.#free
      this.#free = this.#next[slot]
      return slot
    }
    if (this.#allocated === this.#prev.length) this.#grow()
    return this.#allocated++
  }

  #grow(): void {
    const size = this.#prev.length * 2
    const prev = new Int32Array(size)
    const next = new Int32Array(size)
    prev.set(this.#prev)
    next.set(this.#next)
    this.#prev = prev
    this.#next = next
  }

  #remove(slot: number): void {
    this.#unlink(slot)
    this.#index.delete(this.#keys[slot])
    this.#keys[slot] = ''
    this.#values[slot] = ''
    this.#next[slot] = this.#free
    this.#free = slot
  }

  #moveToTail(slot: number): void {
    if (slot === this.#tail) return
    this.#unlink(slot)
    this.#linkTail(slot)
  }

  #linkTail(slot: number): void {
    this.#prev[slot] = this.#tail
    this.#next[slot] = NIL
    if (this.#tail === NIL) this.#head = slot
    else this.#next[this.#tail] = slot
    this.#tail = slot
  }

  #unlink(slot: number): void {
    const p = this.#prev[slot]
    const n = this.#next[slot]
    if (p === NIL) this.#head = n
    else this.#next[p] = n
    if (n === NIL) this.#tail = p
    else this.#prev[n] = p
  }
}

/** Buffered stdout writer. */
class Output {
  #parts: string[] = []
  #length = 0

  line(s: string): void {
    this.#parts.push(s)
    this.#length += s.length + 1
    if (this.#length >= 1 << 16) this.flush()
  }

  flush(): void {
    if (this.#parts.length === 0) return
    const buf = Buffer.from(this.#parts.join('\n') + '\n', 'latin1')
    this.#parts = []
    this.#length = 0
    let off = 0
    while (off < buf.length) {
      try {
        off += writeSync(1, buf, off)
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code !== 'EAGAIN') throw e
      }
    }
  }
}

/** Yields stdin lines (decoded as Latin-1), split on \n, \r\n or \r. */
function* readLines(fd: number): Generator<string> {
  const chunk = Buffer.alloc(1 << 20)
  let pending = ''
  for (;;) {
    let n: number
    try {
      n = readSync(fd, chunk, 0, chunk.length, null)
    } catch (e) {
      const code = (e as NodeJS.ErrnoException).code
      if (code === 'EAGAIN') continue
      if (code === 'EOF') break
      throw e
    }
    if (n === 0) break
    let text = pending + chunk.toString('latin1', 0, n)
    // Hold back a trailing \r: it may be the first half of a \r\n split across chunks.
    const carry = text.endsWith('\r') ? '\r' : ''
    if (carry) text = text.slice(0, -1)
    const lines = text.split(/\r\n|\r|\n/)
    pending = (lines.pop() ?? '') + carry
    yield* lines
  }
  if (pending !== '') yield pending.endsWith('\r') ? pending.slice(0, -1) : pending
}

/** Strips leading and trailing characters <= U+0020, like Java's String.trim. */
function trim(s: string): string {
  let start = 0
  let end = s.length
  while (start < end && s.charCodeAt(start) <= 32) start++
  while (end > start && s.charCodeAt(end - 1) <= 32) end--
  return start === 0 && end === s.length ? s : s.slice(start, end)
}

function runCommand(cache: LruCache, out: Output, line: string): void {
  const sp1 = line.indexOf(' ')
  const op = sp1 < 0 ? line : line.slice(0, sp1)
  const arg = line.slice(sp1 + 1)
  switch (op) {
    case 'SET': {
      const sp2 = arg.indexOf(' ')
      if (sp1 < 0 || sp2 < 0) return
      cache.set(arg.slice(0, sp2), arg.slice(sp2 + 1))
      return
    }
    case 'GET':
      out.line(cache.get(arg) ?? 'NULL')
      return
    case 'DEL':
      out.line(cache.delete(arg) ? '1' : '0')
      return
    case 'SIZE':
      out.line(String(cache.size))
      return
  }
}

function main(): void {
  const out = new Output()
  const lines = readLines(0)
  const first = lines.next()
  if (!first.done) {
    const capacity = Number.parseInt(trim(first.value), 10)
    const cache = new LruCache(capacity)
    for (const raw of lines) {
      const line = trim(raw)
      if (line !== '') runCommand(cache, out, line)
    }
  }
  out.flush()
}

main()
