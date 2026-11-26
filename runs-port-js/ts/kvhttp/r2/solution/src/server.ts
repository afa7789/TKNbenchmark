import http, { type IncomingMessage, type OutgoingHttpHeaders, type ServerResponse } from 'node:http'
import { fileURLToPath } from 'node:url'

const MAX_VALUE_BYTES = 1024 * 1024
const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/

export type Store = Map<string, Buffer>

class HttpError extends Error {
  readonly status: number

  constructor(status: number) {
    super(http.STATUS_CODES[status] ?? String(status))
    this.name = 'HttpError'
    this.status = status
  }
}

function send(res: ServerResponse, status: number, body: Buffer | string = '', headers: OutgoingHttpHeaders = {}): void {
  const noBody = status === 204 || status === 304
  if (noBody) {
    res.writeHead(status, headers)
    res.end()
    return
  }
  const buf = typeof body === 'string' ? Buffer.from(body) : body
  res.writeHead(status, { ...headers, 'Content-Length': buf.length })
  res.end(buf)
}

function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'])
    if (Number.isFinite(declared) && declared > limit) {
      reject(new HttpError(413))
      return
    }
    const chunks: Buffer[] = []
    let size = 0
    const onData = (chunk: Buffer): void => {
      size += chunk.length
      if (size > limit) {
        req.off('data', onData)
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

export function createApp(store: Store = new Map()) {
  async function handleKey(req: IncomingMessage, res: ServerResponse, key: string): Promise<void> {
    if (!KEY_RE.test(key)) throw new HttpError(400)
    switch (req.method) {
      case 'GET': {
        const value = store.get(key)
        if (value === undefined) throw new HttpError(404)
        return send(res, 200, value, { 'Content-Type': 'application/octet-stream' })
      }
      case 'PUT': {
        const value = await readBody(req, MAX_VALUE_BYTES)
        const existed = store.has(key)
        store.set(key, value)
        return send(res, existed ? 200 : 201)
      }
      case 'DELETE':
        if (!store.delete(key)) throw new HttpError(404)
        return send(res, 204)
      default:
        throw new HttpError(405)
    }
  }

  async function route(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const path = req.url ?? '/'
    if (path === '/health') {
      if (req.method !== 'GET') throw new HttpError(405)
      return send(res, 200, 'ok', { 'Content-Type': 'text/plain; charset=utf-8' })
    }
    if (path === '/kv') {
      if (req.method !== 'GET') throw new HttpError(405)
      // Default sort compares UTF-16 code units; keys are ASCII, so this is byte order.
      const keys = [...store.keys()].sort()
      return send(res, 200, JSON.stringify(keys), { 'Content-Type': 'application/json' })
    }
    if (path.startsWith('/kv/')) return handleKey(req, res, path.slice('/kv/'.length))
    throw new HttpError(404)
  }

  return async function handler(req: IncomingMessage, res: ServerResponse): Promise<void> {
    try {
      await route(req, res)
    } catch (err) {
      const status = err instanceof HttpError ? err.status : 500
      if (status === 500) console.error(err)
      if (res.headersSent) {
        res.destroy()
        return
      }
      // Any remaining request body is not worth draining; close after responding.
      send(res, status, '', { Connection: 'close' })
    }
  }
}

function main(argv: readonly string[]): void {
  const port = Number(argv[2])
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('usage: app <port>')
    process.exit(2)
  }
  const server = http.createServer({ maxHeaderSize: 64 * 1024 }, createApp())
  server.on('clientError', (_err, socket) => {
    if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
    else socket.destroy()
  })
  server.listen(port, '127.0.0.1')
  const shutdown = (): void => {
    server.close(() => process.exit(0))
  }
  process.on('SIGTERM', shutdown)
  process.on('SIGINT', shutdown)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main(process.argv)
