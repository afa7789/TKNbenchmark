import http, { type IncomingMessage, type ServerResponse } from 'node:http';
import { KvStore } from './store.ts';

export const MAX_VALUE_BYTES = 1024 * 1024;
const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

class HttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function send(res: ServerResponse, status: number, body?: string | Buffer, contentType?: string): void {
  if (status === 204 || body === undefined) {
    res.writeHead(status, status === 204 ? {} : { 'Content-Length': 0 });
    res.end();
    return;
  }
  const payload = typeof body === 'string' ? Buffer.from(body) : body;
  res.writeHead(status, {
    'Content-Type': contentType ?? 'application/octet-stream',
    'Content-Length': payload.length,
  });
  res.end(payload);
}

function methodNotAllowed(res: ServerResponse, allowed: readonly string[]): void {
  res.setHeader('Allow', allowed.join(', '));
  send(res, 405, 'method not allowed\n', 'text/plain; charset=utf-8');
}

async function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  const declared = Number(req.headers['content-length'] ?? 0);
  if (declared > limit) throw new HttpError(413, 'value too large');
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > limit) throw new HttpError(413, 'value too large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

export function createKvServer(store: KvStore = new KvStore()): http.Server {
  async function handleKey(req: IncomingMessage, res: ServerResponse, key: string): Promise<void> {
    switch (req.method) {
      case 'GET': {
        const value = store.get(key);
        if (value === undefined) send(res, 404, 'not found\n', 'text/plain; charset=utf-8');
        else send(res, 200, value);
        return;
      }
      case 'PUT': {
        const value = await readBody(req, MAX_VALUE_BYTES);
        send(res, store.put(key, value) ? 201 : 200);
        return;
      }
      case 'DELETE':
        if (store.delete(key)) send(res, 204);
        else send(res, 404, 'not found\n', 'text/plain; charset=utf-8');
        return;
      default:
        methodNotAllowed(res, ['GET', 'PUT', 'DELETE']);
    }
  }

  async function route(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const path = req.url ?? '/';
    if (path === '/health') {
      if (req.method === 'GET') send(res, 200, 'ok', 'text/plain; charset=utf-8');
      else methodNotAllowed(res, ['GET']);
      return;
    }
    if (path === '/kv') {
      if (req.method === 'GET') send(res, 200, JSON.stringify(store.keys()), 'application/json');
      else methodNotAllowed(res, ['GET']);
      return;
    }
    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length);
      if (!KEY_PATTERN.test(key)) {
        send(res, 400, 'invalid key\n', 'text/plain; charset=utf-8');
        return;
      }
      await handleKey(req, res, key);
      return;
    }
    send(res, 404, 'not found\n', 'text/plain; charset=utf-8');
  }

  const server = http.createServer((req, res) => {
    route(req, res).catch((err: unknown) => {
      const status = err instanceof HttpError ? err.status : 500;
      if (status === 500) console.error(err);
      if (res.headersSent) {
        res.destroy();
        return;
      }
      res.setHeader('Connection', 'close');
      send(res, status, `${err instanceof HttpError ? err.message : 'internal error'}\n`, 'text/plain; charset=utf-8');
      // Stop reading an oversized or broken body; the socket closes after the response.
      req.resume();
    });
  });
  server.maxConnections = 1024;
  return server;
}
