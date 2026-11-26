import type { IncomingMessage, ServerResponse } from 'node:http';
import type { Store } from './store.ts';

const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

export const MAX_VALUE_BYTES = 1024 * 1024;

interface Response {
  status: number;
  body?: Uint8Array | string;
  contentType?: string;
}

const notFound: Response = { status: 404 };
const methodNotAllowed: Response = { status: 405 };

class PayloadTooLargeError extends Error {}

/**
 * Reads the request body, rejecting with PayloadTooLargeError once it exceeds
 * `limit` bytes. The remainder of an oversized body is drained so the client
 * can still read the error response.
 */
function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    let tooLarge = false;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > limit) {
        tooLarge = true;
        chunks.length = 0;
      } else if (!tooLarge) {
        chunks.push(chunk);
      }
    });
    req.on('end', () => {
      if (tooLarge) reject(new PayloadTooLargeError());
      else resolve(Buffer.concat(chunks, size));
    });
    req.on('error', reject);
  });
}

function health(req: IncomingMessage): Response {
  return req.method === 'GET' ? { status: 200, body: 'ok', contentType: 'text/plain; charset=utf-8' } : methodNotAllowed;
}

function listAll(store: Store, req: IncomingMessage): Response {
  if (req.method !== 'GET') return methodNotAllowed;
  return { status: 200, body: JSON.stringify(store.keys()), contentType: 'application/json' };
}

async function item(store: Store, key: string, req: IncomingMessage): Promise<Response> {
  if (!KEY_PATTERN.test(key)) return { status: 400 };
  switch (req.method) {
    case 'GET': {
      const value = store.get(key);
      return value === undefined ? notFound : { status: 200, body: value, contentType: 'application/octet-stream' };
    }
    case 'PUT': {
      try {
        const value = await readBody(req, MAX_VALUE_BYTES);
        return { status: store.put(key, value) === 'created' ? 201 : 200 };
      } catch (err) {
        if (err instanceof PayloadTooLargeError) return { status: 413 };
        throw err;
      }
    }
    case 'DELETE':
      return store.delete(key) ? { status: 204 } : notFound;
    default:
      return methodNotAllowed;
  }
}

function route(store: Store, req: IncomingMessage): Response | Promise<Response> {
  const url = req.url ?? '/';
  const queryAt = url.indexOf('?');
  const path = queryAt === -1 ? url : url.slice(0, queryAt);
  if (path === '/health') return health(req);
  if (path === '/kv') return listAll(store, req);
  if (path.startsWith(KV_PREFIX)) return item(store, path.slice(KV_PREFIX.length), req);
  return notFound;
}

function send(res: ServerResponse, { status, body, contentType }: Response): void {
  if (status === 204 || body === undefined) {
    res.writeHead(status, status === 204 ? {} : { 'Content-Length': 0 });
    res.end();
    return;
  }
  const payload = typeof body === 'string' ? Buffer.from(body) : body;
  res.writeHead(status, {
    'Content-Length': payload.byteLength,
    ...(contentType === undefined ? {} : { 'Content-Type': contentType }),
  });
  res.end(payload);
}

/** Returns a request listener backed by `store`. */
export function createHandler(store: Store): (req: IncomingMessage, res: ServerResponse) => void {
  return (req, res) => {
    Promise.resolve(route(store, req)).then(
      (response) => send(res, response),
      (err: unknown) => {
        console.error('request failed:', err);
        if (!res.headersSent) send(res, { status: 500 });
        else res.destroy();
      },
    );
  };
}
