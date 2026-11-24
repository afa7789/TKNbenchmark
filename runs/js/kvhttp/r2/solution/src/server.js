'use strict'

const http = require('node:http')

const MAX_VALUE_BYTES = 1024 * 1024
const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/

class HttpError extends Error {
  constructor(status) {
    super(http.STATUS_CODES[status] ?? String(status))
    this.status = status
  }
}

function send(res, status, body = '', headers = {}) {
  const buf = Buffer.isBuffer(body) ? body : Buffer.from(body)
  const noBody = status === 204 || status === 304
  res.writeHead(status, {
    ...headers,
    ...(noBody ? {} : { 'Content-Length': buf.length }),
  })
  res.end(noBody ? undefined : buf)
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'])
    if (Number.isFinite(declared) && declared > limit) {
      reject(new HttpError(413))
      return
    }
    const chunks = []
    let size = 0
    req.on('data', (chunk) => {
      size += chunk.length
      if (size > limit) {
        req.removeAllListeners('data')
        reject(new HttpError(413))
        return
      }
      chunks.push(chunk)
    })
    req.on('end', () => resolve(Buffer.concat(chunks, size)))
    req.on('error', reject)
  })
}

function createApp(store = new Map()) {
  async function handleKey(req, res, key) {
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

  async function route(req, res) {
    const path = req.url
    if (path === '/health') {
      if (req.method !== 'GET') throw new HttpError(405)
      return send(res, 200, 'ok', { 'Content-Type': 'text/plain; charset=utf-8' })
    }
    if (path === '/kv') {
      if (req.method !== 'GET') throw new HttpError(405)
      const keys = [...store.keys()].sort()
      return send(res, 200, JSON.stringify(keys), { 'Content-Type': 'application/json' })
    }
    if (path.startsWith('/kv/')) return handleKey(req, res, path.slice(4))
    throw new HttpError(404)
  }

  return async function handler(req, res) {
    try {
      await route(req, res)
    } catch (err) {
      const status = err instanceof HttpError ? err.status : 500
      if (status === 500) console.error(err)
      if (res.headersSent) {
        res.destroy()
        return
      }
      // Remaining request body (if any) is not worth draining; close after responding.
      send(res, status, '', { Connection: 'close' })
    }
  }
}

function main(argv) {
  const port = Number(argv[2])
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('usage: app <port>')
    process.exit(2)
  }
  const server = http.createServer({ maxHeaderSize: 64 * 1024 }, createApp())
  server.on('clientError', (err, socket) => {
    if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
    else socket.destroy()
  })
  server.listen(port, '127.0.0.1')
  const shutdown = () => server.close(() => process.exit(0))
  process.on('SIGTERM', shutdown)
  process.on('SIGINT', shutdown)
}

module.exports = { createApp }

if (require.main === module) main(process.argv)
