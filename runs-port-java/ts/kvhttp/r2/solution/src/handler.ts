import type { IncomingMessage, RequestListener, ServerResponse } from 'node:http';
import type { KvStore } from './store.ts';

export const MAX_VALUE_BYTES = 1 << 20;

const KEY = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

interface Response {
  readonly status: number;
  readonly contentType?: string;
  readonly body?: Buffer;
}

const empty = (status: number): Response => ({ status });

const text = (status: number, body: string): Response => ({
  status,
  contentType: 'text/plain; charset=utf-8',
  body: Buffer.from(body, 'utf8'),
});

class PayloadTooLargeError extends Error {}

/** Reads the request body, rejecting anything larger than the value limit. */
async function readBody(req: IncomingMessage): Promise<Buffer> {
  const declared = Number(req.headers['content-length']);
  if (Number.isFinite(declared) && declared > MAX_VALUE_BYTES) {
    throw new PayloadTooLargeError();
  }
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > MAX_VALUE_BYTES) throw new PayloadTooLargeError();
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

function rawPath(url: string): string {
  const query = url.indexOf('?');
  return query === -1 ? url : url.slice(0, query);
}

/** Routes requests for the key-value API. */
export class KvRouter {
  readonly #store: KvStore;

  constructor(store: KvStore) {
    this.#store = store;
  }

  async route(req: IncomingMessage): Promise<Response> {
    const method = req.method ?? '';
    const path = rawPath(req.url ?? '');

    if (path === '/health') {
      return method === 'GET' ? text(200, 'ok') : empty(405);
    }
    if (path === '/kv') {
      return method === 'GET' ? this.#listKeys() : empty(405);
    }
    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length);
      if (!KEY.test(key)) return empty(400);
      switch (method) {
        case 'GET': {
          const value = this.#store.get(key);
          return value === undefined
            ? empty(404)
            : { status: 200, contentType: 'application/octet-stream', body: value };
        }
        case 'PUT':
          return empty(this.#store.put(key, await readBody(req)) ? 201 : 200);
        case 'DELETE':
          return empty(this.#store.delete(key) ? 204 : 404);
        default:
          return empty(405);
      }
    }
    return empty(404);
  }

  #listKeys(): Response {
    // Keys are restricted to [A-Za-z0-9_-], so JSON.stringify needs no special escaping.
    return {
      status: 200,
      contentType: 'application/json',
      body: Buffer.from(JSON.stringify(this.#store.keys()), 'utf8'),
    };
  }
}

function send(res: ServerResponse, response: Response): void {
  const body = response.body ?? Buffer.alloc(0);
  if (response.contentType !== undefined) res.setHeader('Content-Type', response.contentType);
  if (response.status !== 204) res.setHeader('Content-Length', body.length);
  res.writeHead(response.status);
  res.end(response.status === 204 ? undefined : body);
}

export function createRequestListener(store: KvStore): RequestListener {
  const router = new KvRouter(store);
  return (req, res) => {
    router.route(req).then(
      (response) => send(res, response),
      (error: unknown) => {
        if (error instanceof PayloadTooLargeError) {
          // Stop reading the oversized body and close once the response is out.
          res.setHeader('Connection', 'close');
          send(res, empty(413));
          req.resume();
          return;
        }
        console.error('request failed:', error);
        if (!res.headersSent) send(res, empty(500));
        else res.destroy();
      },
    );
  };
}
