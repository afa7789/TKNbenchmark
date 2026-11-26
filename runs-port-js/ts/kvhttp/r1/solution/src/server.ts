#!/usr/bin/env node
// kvhttp: an in-memory HTTP/1.1 key-value server.
import http, { type IncomingMessage, type OutgoingHttpHeaders, type ServerResponse } from 'node:http'
import type { Duplex } from 'node:stream'

const MAX_VALUE_BYTES = 1024 * 1024
const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/
const KV_PREFIX = '/kv/'

class HttpError extends Error {
  readonly status: number
  readonly allow: string | undefined

  constructor(status: number, allow?: readonly string[]) {
    super(http.STATUS_CODES[status] ?? String(status))
    this.name = 'HttpError'
    this.status = status
    this.allow = allow?.join(', ')
  }
}

const methodNotAllowed = (allowed: readonly string[]): HttpError => new HttpError(405, allowed)

/** In-memory store: key -> exact value bytes. */
const store = new Map<string, Buffer>()

function send(res: ServerResponse, status: number, body: Buffer | string = '', headers: OutgoingHttpHeaders = {}): void {
  const buf = typeof body === 'string' ? Buffer.from(body) : body
  const noBody = status === 204 || status === 304
  res.writeHead(status, { ...headers, 'Content-Length': noBody ? 0 : buf.length })
  res.end(noBody ? undefined : buf)
}

function readBody(req: IncomingMessage): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'] ?? 0)
    if (declared > MAX_VALUE_BYTES) {
      reject(new HttpError(413))
      return
    }
    const chunks: Buffer[] = []
    let size = 0
    const onData = (chunk: Buffer): void => {
      size += chunk.length
      if (size > MAX_VALUE_BYTES) {
        req.off('data', onData)
        req.resume()
        reject(new HttpError(413))
        return
      }
      chunks.push(chunk)
    }
    req.on('data', onData)
    req.on('end', () => resolve(Buffer.concat(chunks, size)))
    req.on('error', reject)
  })
}

function handleHealth(req: IncomingMessage, res: ServerResponse): void {
  if (req.method !== 'GET') throw methodNotAllowed(['GET'])
  send(res, 200, 'ok', { 'Content-Type': 'text/plain; charset=utf-8' })
}

function handleList(req: IncomingMessage, res: ServerResponse): void {
  if (req.method !== 'GET') throw methodNotAllowed(['GET'])
  const keys = [...store.keys()].sort()
  send(res, 200, JSON.stringify(keys), { 'Content-Type': 'application/json' })
}

function handleItem(req: IncomingMessage, res: ServerResponse, key: string, body: Buffer): void {
  switch (req.method) {
    case 'GET': {
      const value = store.get(key)
      if (value === undefined) throw new HttpError(404)
      send(res, 200, value, { 'Content-Type': 'application/octet-stream' })
      return
    }
    case 'PUT': {
      const existed = store.has(key)
      store.set(key, body)
      send(res, existed ? 200 : 201)
      return
    }
    case 'DELETE': {
      if (!store.delete(key)) throw new HttpError(404)
      send(res, 204)
      return
    }
    default:
      throw methodNotAllowed(['GET', 'PUT', 'DELETE'])
  }
}

async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
  // Always drain the body first so error responses don't reset the connection.
  const body = await readBody(req)
  const path = req.url ?? '/'

  if (path === '/health') return handleHealth(req, res)
  if (path === '/kv') return handleList(req, res)
  if (path.startsWith(KV_PREFIX)) {
    const key = path.slice(KV_PREFIX.length)
    if (!KEY_RE.test(key)) throw new HttpError(400)
    return handleItem(req, res, key, body)
  }
  throw new HttpError(404)
}

function onRequest(req: IncomingMessage, res: ServerResponse): void {
  handle(req, res).catch((err: unknown) => {
    const status = err instanceof HttpError ? err.status : 500
    if (status === 500) console.error(err)
    if (res.headersSent) {
      res.destroy()
      return
    }
    const headers: OutgoingHttpHeaders = { 'Content-Type': 'text/plain; charset=utf-8' }
    if (err instanceof HttpError && err.allow !== undefined) headers['Allow'] = err.allow
    if (status === 413) headers['Connection'] = 'close'
    send(res, status, http.STATUS_CODES[status] ?? '', headers)
  })
}

function onClientError(_err: Error, socket: Duplex): void {
  if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
  else socket.destroy()
}

function parsePort(arg: string | undefined): number | undefined {
  const port = Number(arg)
  return Number.isInteger(port) && port >= 1 && port <= 65535 ? port : undefined
}

function main(): void {
  const port = parsePort(process.argv[2])
  if (port === undefined) {
    console.error('usage: app <port>')
    process.exit(2)
  }
  const server = http.createServer({ keepAlive: false }, onRequest)
  server.maxConnections = Infinity
  server.on('clientError', onClientError)
  server.on('error', (err) => {
    console.error(err.message)
    process.exit(1)
  })
  server.listen({ port, host: '127.0.0.1', backlog: 1024 })

  const shutdown = (): void => {
    server.close(() => process.exit(0))
  }
  process.on('SIGTERM', shutdown)
  process.on('SIGINT', shutdown)
}

main()
