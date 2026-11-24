import http from 'node:http';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { KvStore } from './store.ts';

export const MAX_VALUE_BYTES = 1024 * 1024;
const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
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
  body: Buffer | string = '',
  contentType?: string,
): void {
  const payload = typeof body === 'string' ? Buffer.from(body) : body;
  const headers: http.OutgoingHttpHeaders = { 'Content-Length': payload.length };
  if (contentType) headers['Content-Type'] = contentType;
  res.writeHead(status, headers);
  res.end(payload);
}

function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'] ?? 0);
    if (declared > limit) {
      reject(new HttpError(413));
      return;
    }
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

function methodNotAllowed(res: ServerResponse, allowed: readonly string[]): void {
  res.setHeader('Allow', allowed.join(', '));
  send(res, 405);
}

export function createApp(store: KvStore = new KvStore()): http.Server {
  async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const method = req.method ?? 'GET';
    const path = (req.url ?? '/').split('?', 1)[0];

    if (path === '/health') {
      if (method !== 'GET') return methodNotAllowed(res, ['GET']);
      return send(res, 200, 'ok', 'text/plain; charset=utf-8');
    }

    if (path === '/kv') {
      if (method !== 'GET') return methodNotAllowed(res, ['GET']);
      return send(res, 200, JSON.stringify(store.keys()), 'application/json');
    }

    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length);
      if (!KEY_PATTERN.test(key)) return send(res, 400);

      switch (method) {
        case 'GET': {
          const value = store.get(key);
          return value ? send(res, 200, value, 'application/octet-stream') : send(res, 404);
        }
        case 'PUT': {
          const value = await readBody(req, MAX_VALUE_BYTES);
          return send(res, store.set(key, value) ? 201 : 200);
        }
        case 'DELETE':
          return send(res, store.delete(key) ? 204 : 404);
        default:
          return methodNotAllowed(res, ['GET', 'PUT', 'DELETE']);
      }
    }

    send(res, 404);
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((err: unknown) => {
      const status = err instanceof HttpError ? err.status : 500;
      if (status === 500) console.error(err);
      if (!res.headersSent) {
        res.setHeader('Connection', 'close');
        send(res, status);
      } else {
        res.destroy();
      }
    });
  });
  server.keepAliveTimeout = 5000;
  return server;
}
