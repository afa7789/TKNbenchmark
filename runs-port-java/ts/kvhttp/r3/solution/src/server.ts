import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { KvStore } from './store.ts';

const KEY = /^[A-Za-z0-9_-]{1,64}$/;
export const MAX_VALUE_BYTES = 1 << 20;
const KV_PREFIX = '/kv/';

interface Response {
  status: number;
  contentType?: string;
  body?: Buffer;
}

const status = (code: number): Response => ({ status: code });

class PayloadTooLargeError extends Error {}

/** Reads the request body, rejecting with PayloadTooLargeError past `limit` bytes. */
async function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > limit) throw new PayloadTooLargeError();
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

export class KvRouter {
  readonly #store: KvStore;

  constructor(store = new KvStore()) {
    this.#store = store;
  }

  async route(req: IncomingMessage): Promise<Response> {
    const method = req.method ?? '';
    const path = rawPath(req.url ?? '');

    if (path === '/health') {
      return method === 'GET'
        ? { status: 200, contentType: 'text/plain; charset=utf-8', body: Buffer.from('ok') }
        : status(405);
    }
    if (path === '/kv') {
      return method === 'GET' ? this.#listKeys() : status(405);
    }
    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length);
      if (!KEY.test(key)) return status(400);
      switch (method) {
        case 'GET': {
          const value = this.#store.get(key);
          return value === undefined ? status(404) : { status: 200, body: value };
        }
        case 'PUT':
          return this.#put(req, key);
        case 'DELETE':
          return status(this.#store.delete(key) ? 204 : 404);
        default:
          return status(405);
      }
    }
    return status(404);
  }

  async #put(req: IncomingMessage, key: string): Promise<Response> {
    const declared = req.headers['content-length'];
    if (declared !== undefined && Number(declared) > MAX_VALUE_BYTES) return status(413);
    let value: Buffer;
    try {
      value = await readBody(req, MAX_VALUE_BYTES);
    } catch (err) {
      if (err instanceof PayloadTooLargeError) return status(413);
      throw err;
    }
    return status(this.#store.put(key, value) ? 201 : 200);
  }

  #listKeys(): Response {
    // Keys are restricted to [A-Za-z0-9_-], so JSON.stringify needs no escaping beyond quoting.
    const body = Buffer.from(JSON.stringify(this.#store.keys()));
    return { status: 200, contentType: 'application/json', body };
  }
}

/** Strips any query string or fragment from a request target, leaving the raw path. */
function rawPath(target: string): string {
  const end = target.search(/[?#]/);
  return end === -1 ? target : target.slice(0, end);
}

function send(res: ServerResponse, response: Response): void {
  const headers: Record<string, string | number> = { Connection: 'close' };
  if (response.contentType !== undefined) headers['Content-Type'] = response.contentType;
  if (response.status === 204) {
    res.writeHead(204, headers).end();
    return;
  }
  const body = response.body ?? Buffer.alloc(0);
  headers['Content-Length'] = body.length;
  res.writeHead(response.status, headers).end(body);
}

export function createKvServer(router = new KvRouter()): Server {
  const server = createServer({ requireHostHeader: false }, (req, res) => {
    router.route(req).then(
      (response) => send(res, response),
      (err: unknown) => {
        if (res.headersSent || req.destroyed) {
          res.destroy();
          return;
        }
        console.error('request failed', err);
        send(res, status(500));
      },
    );
  });
  // Connections are one-shot; don't let idle sockets linger.
  server.keepAliveTimeout = 1000;
  return server;
}
