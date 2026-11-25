import http, { type IncomingMessage, type ServerResponse } from 'node:http';
import { KvStore } from './store.ts';

export const MAX_VALUE_BYTES = 1024 * 1024;
const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

class HttpError extends Error {
  readonly status: number;
  constructor(status: number, message?: string) {
    super(message ?? http.STATUS_CODES[status] ?? 'Error');
    this.status = status;
  }
}

function send(
  res: ServerResponse,
  status: number,
  body: string | Buffer = '',
  contentType?: string,
): void {
  const payload = typeof body === 'string' ? Buffer.from(body) : body;
  const headers: http.OutgoingHttpHeaders = { 'Content-Length': payload.length };
  if (contentType) headers['Content-Type'] = contentType;
  res.writeHead(status, headers);
  res.end(payload);
}

function allow(res: ServerResponse, methods: readonly string[]): never {
  res.setHeader('Allow', methods.join(', '));
  throw new HttpError(405);
}

async function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  const declared = Number(req.headers['content-length'] ?? 0);
  if (declared > limit) throw new HttpError(413);
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > limit) throw new HttpError(413);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

async function route(store: KvStore, req: IncomingMessage, res: ServerResponse): Promise<void> {
  const method = req.method ?? '';
  const path = req.url ?? '/';

  if (path === '/health') {
    if (method !== 'GET') allow(res, ['GET']);
    return send(res, 200, 'ok', 'text/plain; charset=utf-8');
  }

  if (path === '/kv') {
    if (method !== 'GET') allow(res, ['GET']);
    return send(res, 200, JSON.stringify(store.keys()), 'application/json');
  }

  if (path.startsWith(KV_PREFIX)) {
    const key = path.slice(KV_PREFIX.length);
    if (!KEY_RE.test(key)) throw new HttpError(400, 'invalid key');

    switch (method) {
      case 'GET': {
        const value = store.get(key);
        if (!value) throw new HttpError(404);
        return send(res, 200, value, 'application/octet-stream');
      }
      case 'PUT': {
        const value = await readBody(req, MAX_VALUE_BYTES);
        return send(res, store.put(key, value) ? 201 : 200);
      }
      case 'DELETE':
        if (!store.delete(key)) throw new HttpError(404);
        return send(res, 204);
      default:
        allow(res, ['GET', 'PUT', 'DELETE']);
    }
  }

  throw new HttpError(404);
}

export function createServer(store: KvStore = new KvStore()): http.Server {
  return http.createServer(async (req, res) => {
    try {
      await route(store, req, res);
    } catch (err) {
      const status = err instanceof HttpError ? err.status : 500;
      if (status === 500) console.error(err);
      if (res.headersSent) {
        res.destroy();
        return;
      }
      // Don't try to keep reading an oversized or failed body.
      if (!req.complete) res.setHeader('Connection', 'close');
      send(res, status, status === 204 ? '' : `${http.STATUS_CODES[status] ?? 'Error'}\n`, 'text/plain; charset=utf-8');
    }
  });
}
