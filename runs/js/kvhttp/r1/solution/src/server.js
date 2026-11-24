#!/usr/bin/env node
// kvhttp: an in-memory HTTP/1.1 key-value server.
import http from 'node:http'

const MAX_VALUE_BYTES = 1024 * 1024
const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/
const KV_PREFIX = '/kv/'

class HttpError extends Error {
  constructor(status) {
    super(http.STATUS_CODES[status] ?? String(status))
    this.status = status
  }
}

/** Store maps key -> Buffer. */
const store = new Map()

function send(res, status, body = '', headers = {}) {
  const buf = Buffer.isBuffer(body) ? body : Buffer.from(body)
  res.writeHead(status, { ...headers, 'Content-Length': buf.length })
  res.end(status === 204 ? undefined : buf)
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'] ?? 0)
    if (declared > MAX_VALUE_BYTES) {
      reject(new HttpError(413))
      return
    }
    const chunks = []
    let size = 0
    req.on('data', (chunk) => {
      size += chunk.length
      if (size > MAX_VALUE_BYTES) {
        req.removeAllListeners('data')
        req.resume()
        reject(new HttpError(413))
        return
      }
      chunks.push(chunk)
    })
    req.on('end', () => resolve(Buffer.concat(chunks, size)))
    req.on('error', reject)
  })
}

function methodNotAllowed(allowed) {
  const err = new HttpError(405)
  err.allow = allowed.join(', ')
  return err
}

const handlers = {
  health(req, res) {
    if (req.method !== 'GET') throw methodNotAllowed(['GET'])
    send(res, 200, 'ok', { 'Content-Type': 'text/plain; charset=utf-8' })
  },

  list(req, res) {
    if (req.method !== 'GET') throw methodNotAllowed(['GET'])
    const keys = [...store.keys()].sort()
    send(res, 200, JSON.stringify(keys), { 'Content-Type': 'application/json' })
  },

  item(req, res, key, body) {
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
      case 'DELETE':
        if (!store.delete(key)) throw new HttpError(404)
        send(res, 204)
        return
      default:
        throw methodNotAllowed(['GET', 'PUT', 'DELETE'])
    }
  },
}

async function handle(req, res) {
  // Always drain the body first so error responses don't reset the connection.
  const body = await readBody(req)
  const path = req.url ?? '/'

  if (path === '/health') return handlers.health(req, res)
  if (path === '/kv') return handlers.list(req, res)
  if (path.startsWith(KV_PREFIX)) {
    const key = path.slice(KV_PREFIX.length)
    if (!KEY_RE.test(key)) throw new HttpError(400)
    return handlers.item(req, res, key, body)
  }
  throw new HttpError(404)
}

function onRequest(req, res) {
  handle(req, res).catch((err) => {
    const status = err instanceof HttpError ? err.status : 500
    if (status === 500) console.error(err)
    if (res.headersSent) {
      res.destroy()
      return
    }
    const headers = { 'Content-Type': 'text/plain; charset=utf-8' }
    if (err.allow) headers.Allow = err.allow
    if (status === 413) headers.Connection = 'close'
    send(res, status, http.STATUS_CODES[status] ?? '', headers)
  })
}

function main() {
  const port = Number(process.argv[2])
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('usage: app <port>')
    process.exit(2)
  }
  const server = http.createServer({ keepAlive: false }, onRequest)
  server.maxConnections = Infinity
  server.on('clientError', (err, socket) => {
    if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
    else socket.destroy()
  })
  server.on('error', (err) => {
    console.error(err.message)
    process.exit(1)
  })
  server.listen({ port, host: '127.0.0.1', backlog: 1024 })

  const shutdown = () => server.close(() => process.exit(0))
  process.on('SIGTERM', shutdown)
  process.on('SIGINT', shutdown)
}

main()
