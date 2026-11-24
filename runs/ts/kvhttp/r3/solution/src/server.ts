import http, { type IncomingMessage, type ServerResponse } from 'node:http';
import { KvStore } from './store.ts';

export const MAX_VALUE_BYTES = 1024 * 1024;
const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

class HttpError extends Error {
  readonly status: number;
  readonly headers: Record<string, string>;
  constructor(status: number, message?: string, headers: Record<string, string> = {}) {
    super(message ?? http.STATUS_CODES[status] ?? 'Error');
    this.status = status;
    this.headers = headers;
  }
}

type Body = string | Buffer;

function send(
  res: ServerResponse,
  status: number,
  body: Body = '',
  contentType = 'text/plain; charset=utf-8',
  extraHeaders: Record<string, string> = {},
): void {
  const payload = typeof body === 'string' ? Buffer.from(body, 'utf8') : body;
  const headers: Record<string, string | number> = { ...extraHeaders, 'Content-Length': payload.length };
  if (payload.length > 0) headers['Content-Type'] = contentType;
  res.writeHead(status, headers);
  res.end(payload);
}

function methodNotAllowed(allowed: readonly string[]): never {
  throw new HttpError(405, undefined, { Allow: allowed.join(', ') });
}

function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  const declared = req.headers['content-length'];
  if (declared !== undefined && Number(declared) > limit) {
    return Promise.reject(new HttpError(413));
  }
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > limit) {
        reject(new HttpError(413));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks, size)));
    req.on('error', reject);
  });
}

async function route(store: KvStore, req: IncomingMessage, res: ServerResponse): Promise<void> {
  const method = req.method ?? '';
  const path = req.url ?? '/';

  if (path === '/health') {
    if (method !== 'GET') methodNotAllowed(['GET']);
    send(res, 200, 'ok');
    return;
  }

  if (path === '/kv') {
    if (method !== 'GET') methodNotAllowed(['GET']);
    send(res, 200, JSON.stringify(store.keys()), 'application/json');
    return;
  }

  if (path.startsWith(KV_PREFIX)) {
    const key = path.slice(KV_PREFIX.length);
    if (!KEY_PATTERN.test(key)) throw new HttpError(400, 'invalid key');

    switch (method) {
      case 'GET': {
        const value = store.get(key);
        if (value === undefined) throw new HttpError(404);
        send(res, 200, value, 'application/octet-stream');
        return;
      }
      case 'PUT': {
        const value = await readBody(req, MAX_VALUE_BYTES);
        send(res, store.set(key, value) ? 201 : 200);
        return;
      }
      case 'DELETE':
        if (!store.delete(key)) throw new HttpError(404);
        send(res, 204);
        return;
      default:
        methodNotAllowed(['GET', 'PUT', 'DELETE']);
    }
  }

  throw new HttpError(404);
}

export function createServer(store: KvStore = new KvStore()): http.Server {
  const server = http.createServer({ keepAliveTimeout: 5000 }, (req, res) => {
    route(store, req, res).catch((err: unknown) => {
      if (res.headersSent) {
        res.destroy();
        return;
      }
      if (err instanceof HttpError) {
        send(res, err.status, err.message, undefined, err.headers);
        if (err.status === 413) res.once('finish', () => req.socket.destroy());
        return;
      }
      console.error(err);
      send(res, 500, 'internal error');
    });
  });
  server.maxConnections = 1024;
  return server;
}
