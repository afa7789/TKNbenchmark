/**
 * Minimal HTTP/1.1 message handling: request parsing from a byte stream and
 * response serialisation. One request is read per connection.
 */

import { STATUS_CODES } from 'node:http'
import type { Socket } from 'node:net'

export const MAX_VALUE_BYTES = 1024 * 1024
export const MAX_HEADER_BYTES = 64 * 1024

export const Status = {
  OK: 200,
  CREATED: 201,
  NO_CONTENT: 204,
  NOT_MODIFIED: 304,
  BAD_REQUEST: 400,
  NOT_FOUND: 404,
  METHOD_NOT_ALLOWED: 405,
  CONTENT_TOO_LARGE: 413,
  REQUEST_HEADER_FIELDS_TOO_LARGE: 431,
  INTERNAL_SERVER_ERROR: 500,
} as const

export type StatusCode = (typeof Status)[keyof typeof Status]

/** A protocol-level failure that should be answered with `status`. */
export class HttpError extends Error {
  readonly status: StatusCode

  constructor(status: StatusCode) {
    super(STATUS_CODES[status] ?? String(status))
    this.name = 'HttpError'
    this.status = status
  }
}

/** The peer closed the connection before a complete request arrived. */
export class IncompleteReadError extends Error {
  constructor() {
    super('connection closed before the request was complete')
    this.name = 'IncompleteReadError'
  }
}

/** A delimiter was not found within the allowed number of bytes. */
export class LimitOverrunError extends Error {
  constructor() {
    super('delimiter not found within limit')
    this.name = 'LimitOverrunError'
  }
}

export interface Request {
  readonly method: string
  readonly path: string
  readonly headers: ReadonlyMap<string, string>
  readonly body: Buffer
}

export class Response {
  readonly status: StatusCode
  readonly body: Buffer
  readonly headers: Readonly<Record<string, string>>

  constructor(status: StatusCode, body: Buffer = Buffer.alloc(0), headers: Record<string, string> = {}) {
    this.status = status
    this.body = body
    this.headers = headers
  }

  encode(): Buffer {
    const headers: Record<string, string> = {
      'Content-Length': String(this.body.length),
      Connection: 'close',
      ...this.headers,
    }
    if (this.status === Status.NO_CONTENT || this.status === Status.NOT_MODIFIED) {
      delete headers['Content-Length']
    }
    const lines = [`HTTP/1.1 ${this.status} ${STATUS_CODES[this.status] ?? ''}`]
    for (const [name, value] of Object.entries(headers)) lines.push(`${name}: ${value}`)
    const head = Buffer.from(lines.join('\r\n') + '\r\n\r\n', 'latin1')
    return Buffer.concat([head, this.body])
  }
}

/**
 * Promise-based buffered reader over a socket, in the spirit of asyncio's
 * StreamReader. Applies backpressure by pausing the socket while enough data
 * is buffered and nobody is waiting for more.
 */
export class StreamReader {
  readonly #socket: Socket
  readonly #highWaterMark: number
  #chunks: Buffer[] = []
  #buffered = 0
  #ended = false
  #error: Error | null = null
  #wake: (() => void) | null = null

  constructor(socket: Socket, highWaterMark = MAX_VALUE_BYTES + MAX_HEADER_BYTES) {
    this.#socket = socket
    this.#highWaterMark = highWaterMark
    socket.on('data', (chunk: Buffer) => {
      this.#chunks.push(chunk)
      this.#buffered += chunk.length
      if (this.#buffered >= this.#highWaterMark) socket.pause()
      this.#notify()
    })
    socket.on('end', () => {
      this.#ended = true
      this.#notify()
    })
    socket.on('close', () => {
      this.#ended = true
      this.#notify()
    })
    socket.on('error', (err) => {
      this.#error = err
      this.#notify()
    })
  }

  /** Read up to and including `delimiter`. Throws LimitOverrunError if it is not found within `limit` bytes. */
  async readUntil(delimiter: Buffer, limit: number = MAX_HEADER_BYTES): Promise<Buffer> {
    let searchFrom = 0
    for (;;) {
      const buf = this.#peek()
      const at = buf.indexOf(delimiter, searchFrom)
      if (at >= 0) return this.#take(at + delimiter.length)
      if (buf.length > limit) throw new LimitOverrunError()
      searchFrom = Math.max(0, buf.length - delimiter.length + 1)
      await this.#more()
    }
  }

  /** Read exactly `n` bytes. Throws IncompleteReadError on EOF. */
  async readExactly(n: number): Promise<Buffer> {
    while (this.#buffered < n) await this.#more()
    return this.#take(n)
  }

  #peek(): Buffer {
    if (this.#chunks.length > 1) this.#chunks = [Buffer.concat(this.#chunks, this.#buffered)]
    return this.#chunks[0] ?? Buffer.alloc(0)
  }

  #take(n: number): Buffer {
    const buf = this.#peek()
    const out = buf.subarray(0, n)
    const rest = buf.subarray(n)
    this.#chunks = rest.length > 0 ? [rest] : []
    this.#buffered = rest.length
    return out
  }

  async #more(): Promise<void> {
    if (this.#error) throw this.#error
    if (this.#ended) throw new IncompleteReadError()
    const before = this.#buffered
    await new Promise<void>((resolve) => {
      this.#wake = resolve
      this.#socket.resume()
    })
    if (this.#error) throw this.#error
    if (this.#buffered === before && this.#ended) throw new IncompleteReadError()
  }

  #notify(): void {
    const wake = this.#wake
    this.#wake = null
    wake?.()
  }
}

const CRLF = Buffer.from('\r\n')
const HEADER_END = Buffer.from('\r\n\r\n')
const DIGITS = /^[0-9]+$/
const HEX_DIGITS = /^[0-9A-Fa-f]+$/

export async function readRequest(reader: StreamReader): Promise<Request> {
  let head: Buffer
  try {
    head = await reader.readUntil(HEADER_END, MAX_HEADER_BYTES)
  } catch (err) {
    if (err instanceof LimitOverrunError) throw new HttpError(Status.REQUEST_HEADER_FIELDS_TOO_LARGE)
    throw err
  }

  const [requestLine = '', ...headerLines] = head
    .subarray(0, head.length - HEADER_END.length)
    .toString('latin1')
    .split('\r\n')
  const parts = requestLine.split(' ')
  if (parts.length !== 3 || !parts[2]!.startsWith('HTTP/')) throw new HttpError(Status.BAD_REQUEST)
  const [method, target] = parts as [string, string, string]

  const headers = new Map<string, string>()
  for (const line of headerLines) {
    const sep = line.indexOf(':')
    const name = sep < 0 ? '' : line.slice(0, sep)
    if (!name || name !== name.trim()) throw new HttpError(Status.BAD_REQUEST)
    headers.set(name.toLowerCase(), line.slice(sep + 1).trim())
  }

  let body: Buffer
  if ((headers.get('transfer-encoding') ?? '').toLowerCase().includes('chunked')) {
    body = await readChunked(reader)
  } else {
    const rawLength = headers.get('content-length') ?? '0'
    if (!DIGITS.test(rawLength)) throw new HttpError(Status.BAD_REQUEST)
    const length = Number(rawLength)
    if (length > MAX_VALUE_BYTES) throw new HttpError(Status.CONTENT_TOO_LARGE)
    body = await reader.readExactly(length)
  }

  const query = target.indexOf('?')
  const path = query < 0 ? target : target.slice(0, query)
  return { method, path, headers, body }
}

async function readChunked(reader: StreamReader): Promise<Buffer> {
  const chunks: Buffer[] = []
  let total = 0
  for (;;) {
    const line = await reader.readUntil(CRLF)
    const sizeText = line.subarray(0, line.length - CRLF.length).toString('latin1').split(';', 1)[0]!.trim()
    if (!HEX_DIGITS.test(sizeText)) throw new HttpError(Status.BAD_REQUEST)
    const size = Number.parseInt(sizeText, 16)
    if (size === 0) {
      // Skip trailers up to the terminating blank line.
      while ((await reader.readUntil(CRLF)).length !== CRLF.length);
      return Buffer.concat(chunks, total)
    }
    if (total + size > MAX_VALUE_BYTES) throw new HttpError(Status.CONTENT_TOO_LARGE)
    chunks.push(await reader.readExactly(size))
    total += size
    if (!(await reader.readExactly(CRLF.length)).equals(CRLF)) throw new HttpError(Status.BAD_REQUEST)
  }
}
