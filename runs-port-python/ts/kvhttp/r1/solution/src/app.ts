/** Routing and the in-memory key-value store. */

import { Response, Status, type Request } from './http.ts'

const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/
const KV_PREFIX = '/kv/'

/** In-memory store. Accessed only from the event loop, so no locking is needed. */
export class KVStore {
  readonly #data = new Map<string, Buffer>()

  /** Store a value; returns true if the key was new. */
  put(key: string, value: Buffer): boolean {
    const created = !this.#data.has(key)
    // Copy so the stored value does not pin the connection's read buffer.
    this.#data.set(key, Buffer.from(value))
    return created
  }

  get(key: string): Buffer | undefined {
    return this.#data.get(key)
  }

  delete(key: string): boolean {
    return this.#data.delete(key)
  }

  /** Every key, sorted ascending. */
  keys(): string[] {
    return [...this.#data.keys()].sort()
  }
}

export class App {
  readonly store: KVStore

  constructor(store: KVStore = new KVStore()) {
    this.store = store
  }

  handle(req: Request): Response {
    const { path } = req
    if (path === '/health') {
      if (req.method === 'GET') return new Response(Status.OK, Buffer.from('ok'), { 'Content-Type': 'text/plain' })
      return methodNotAllowed('GET')
    }
    if (path === '/kv') {
      if (req.method === 'GET') {
        const body = Buffer.from(JSON.stringify(this.store.keys()))
        return new Response(Status.OK, body, { 'Content-Type': 'application/json' })
      }
      return methodNotAllowed('GET')
    }
    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length)
      if (!KEY_RE.test(key)) return new Response(Status.BAD_REQUEST)
      return this.#handleKey(req, key)
    }
    return new Response(Status.NOT_FOUND)
  }

  #handleKey(req: Request, key: string): Response {
    switch (req.method) {
      case 'GET': {
        const value = this.store.get(key)
        if (value === undefined) return new Response(Status.NOT_FOUND)
        return new Response(Status.OK, value, { 'Content-Type': 'application/octet-stream' })
      }
      case 'PUT':
        return new Response(this.store.put(key, req.body) ? Status.CREATED : Status.OK)
      case 'DELETE':
        return new Response(this.store.delete(key) ? Status.NO_CONTENT : Status.NOT_FOUND)
      default:
        return methodNotAllowed('GET, PUT, DELETE')
    }
  }
}

function methodNotAllowed(allow: string): Response {
  return new Response(Status.METHOD_NOT_ALLOWED, undefined, { Allow: allow })
}
