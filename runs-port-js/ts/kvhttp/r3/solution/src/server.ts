import http, { type IncomingMessage, type Server, type ServerResponse } from 'node:http'

export const MAX_VALUE_BYTES = 1024 * 1024
const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/

export type Store = Map<string, Buffer>

class HttpError extends Error {
  readonly status: number

  constructor(status: number, message: string = http.STATUS_CODES[status] ?? 'Error') {
    super(message)
    this.name = 'HttpError'
    this.status = status
  }
}

function send(
  res: ServerResponse,
  status: number,
  body: Buffer | null = null,
  contentType = 'text/plain; charset=utf-8',
): void {
  const headers: http.OutgoingHttpHeaders = {}
  if (body !== null && body.length > 0) headers['Content-Type'] = contentType
  // 204 must not carry a body or a Content-Length header.
  if (status !== 204) headers['Content-Length'] = body?.length ?? 0
  res.writeHead(status, headers)
  if (status === 204 || body === null) res.end()
  else res.end(body)
}

function sendError(res: ServerResponse, status: number): void {
  send(res, status, Buffer.from(http.STATUS_CODES[status] ?? 'Error'))
}

/** Reads the request body, enforcing the size limit. */
function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'])
    if (Number.isFinite(declared) && declared > limit) {
      reject(new HttpError(413))
      return
    }
    const chunks: Buffer[] = []
    let size = 0
    req.on('data', (chunk: Buffer) => {
      size += chunk.length
      if (size > limit) {
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

function methodNotAllowed(res: ServerResponse, methods: readonly string[]): never {
  res.setHeader('Allow', methods.join(', '))
  throw new HttpError(405)
}

export function createApp(store: Store = new Map()): Server {
  async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const path = (req.url ?? '/').split('?', 1)[0] ?? '/'
    const { method } = req

    if (path === '/health') {
      if (method !== 'GET') methodNotAllowed(res, ['GET'])
      return send(res, 200, Buffer.from('ok'))
    }

    if (path === '/kv') {
      if (method !== 'GET') methodNotAllowed(res, ['GET'])
      const keys = [...store.keys()].sort()
      return send(res, 200, Buffer.from(JSON.stringify(keys)), 'application/json')
    }

    if (path.startsWith('/kv/')) {
      const key = path.slice('/kv/'.length)
      if (!KEY_RE.test(key)) throw new HttpError(400)
      switch (method) {
        case 'GET': {
          const value = store.get(key)
          if (value === undefined) throw new HttpError(404)
          return send(res, 200, value, 'application/octet-stream')
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
          methodNotAllowed(res, ['GET', 'PUT', 'DELETE'])
      }
    }

    throw new HttpError(404)
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((err: unknown) => {
      const status = err instanceof HttpError ? err.status : 500
      if (status === 500) console.error(err)
      if (res.headersSent) {
        res.destroy()
        return
      }
      if (status === 413) res.setHeader('Connection', 'close')
      sendError(res, status)
    })
  })
  server.keepAliveTimeout = 5000
  server.headersTimeout = 30000
  server.requestTimeout = 60000
  return server
}
