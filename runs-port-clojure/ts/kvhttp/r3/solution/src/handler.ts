import type { IncomingMessage, ServerResponse } from 'node:http';
import type { Store } from './store.ts';

const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

/** Bodies larger than this are rejected; values are capped at 1 MiB, so this leaves headroom. */
export const MAX_BODY_BYTES = 8 * 1024 * 1024;

interface Response {
  status: number;
  body?: Buffer | string;
  contentType?: string;
}

class PayloadTooLargeError extends Error {}

const methodNotAllowed: Response = { status: 405 };
const notFound: Response = { status: 404 };

function readBody(req: IncomingMessage): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'] ?? 0);
    if (declared > MAX_BODY_BYTES) {
      reject(new PayloadTooLargeError());
      return;
    }
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new PayloadTooLargeError());
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks, size)));
    req.on('error', reject);
  });
}

function health(method: string): Response {
  return method === 'GET' ? { status: 200, body: 'ok', contentType: 'text/plain' } : methodNotAllowed;
}

function listKeys(store: Store, method: string): Response {
  if (method !== 'GET') return methodNotAllowed;
  return { status: 200, body: JSON.stringify(store.keys()), contentType: 'application/json' };
}

async function entry(store: Store, key: string, req: IncomingMessage): Promise<Response> {
  switch (req.method) {
    case 'GET': {
      const value = store.fetch(key);
      return value ? { status: 200, body: value, contentType: 'application/octet-stream' } : notFound;
    }
    case 'PUT':
      return { status: store.put(key, await readBody(req)) === 'created' ? 201 : 200 };
    case 'DELETE':
      return store.delete(key) ? { status: 204 } : notFound;
    default:
      return methodNotAllowed;
  }
}

async function route(store: Store, req: IncomingMessage): Promise<Response> {
  const method = req.method ?? '';
  const url = req.url ?? '/';
  const queryAt = url.indexOf('?');
  const path = queryAt === -1 ? url : url.slice(0, queryAt);

  if (path === '/health') return health(method);
  if (path === '/kv') return listKeys(store, method);
  if (path.startsWith(KV_PREFIX)) {
    const key = path.slice(KV_PREFIX.length);
    return KEY_PATTERN.test(key) ? entry(store, key, req) : { status: 400 };
  }
  return notFound;
}

function send(res: ServerResponse, { status, body, contentType }: Response): void {
  const payload = body === undefined ? undefined : typeof body === 'string' ? Buffer.from(body) : body;
  const headers: Record<string, string | number> = {};
  if (status !== 204) headers['Content-Length'] = payload?.length ?? 0;
  if (contentType && payload) headers['Content-Type'] = contentType;
  res.writeHead(status, headers);
  res.end(payload);
}

/** Returns a Node request listener serving the kvhttp API from `store`. */
export function makeHandler(store: Store): (req: IncomingMessage, res: ServerResponse) => void {
  return (req, res) => {
    route(store, req).then(
      (response) => {
        // Drain any unread request body so the connection closes cleanly.
        req.resume();
        send(res, response);
      },
      (err: unknown) => {
        if (res.headersSent || res.destroyed) return;
        res.shouldKeepAlive = false;
        send(res, { status: err instanceof PayloadTooLargeError ? 413 : 500 });
      },
    );
  };
}
