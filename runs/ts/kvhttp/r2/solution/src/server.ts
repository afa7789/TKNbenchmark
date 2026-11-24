import http, { type IncomingMessage, type ServerResponse } from 'node:http';
import { KvStore } from './store.ts';

export const MAX_VALUE_BYTES = 1024 * 1024;
const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

class PayloadTooLargeError extends Error {}

function send(
  res: ServerResponse,
  status: number,
  body: string | Buffer = '',
  headers: Record<string, string> = {},
): void {
  const payload = typeof body === 'string' ? Buffer.from(body) : body;
  res.writeHead(status, { ...headers, 'Content-Length': payload.length });
  res.end(payload);
}

function methodNotAllowed(res: ServerResponse, allowed: readonly string[]): void {
  send(res, 405, '', { Allow: allowed.join(', ') });
}

/** Reads the full request body, rejecting bodies larger than `limit` bytes. */
function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length']);
    if (Number.isFinite(declared) && declared > limit) {
      reject(new PayloadTooLargeError());
      return;
    }
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > limit) {
        req.removeAllListeners('data');
        reject(new PayloadTooLargeError());
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks, size)));
    req.on('error', reject);
  });
}

async function handleKey(
  store: KvStore,
  req: IncomingMessage,
  res: ServerResponse,
  key: string,
): Promise<void> {
  switch (req.method) {
    case 'GET': {
      const value = store.get(key);
      if (value === undefined) send(res, 404);
      else send(res, 200, value, { 'Content-Type': 'application/octet-stream' });
      return;
    }
    case 'PUT': {
      const value = await readBody(req, MAX_VALUE_BYTES);
      send(res, store.put(key, value) ? 201 : 200);
      return;
    }
    case 'DELETE':
      send(res, store.delete(key) ? 204 : 404);
      return;
    default:
      methodNotAllowed(res, ['GET', 'PUT', 'DELETE']);
  }
}

async function route(store: KvStore, req: IncomingMessage, res: ServerResponse): Promise<void> {
  const path = (req.url ?? '/').split('?', 1)[0];

  if (path === '/health') {
    if (req.method === 'GET') send(res, 200, 'ok', { 'Content-Type': 'text/plain' });
    else methodNotAllowed(res, ['GET']);
    return;
  }

  if (path === '/kv') {
    if (req.method === 'GET') {
      send(res, 200, JSON.stringify(store.keys()), { 'Content-Type': 'application/json' });
    } else {
      methodNotAllowed(res, ['GET']);
    }
    return;
  }

  if (path.startsWith(KV_PREFIX)) {
    const key = path.slice(KV_PREFIX.length);
    if (!KEY_PATTERN.test(key)) send(res, 400);
    else await handleKey(store, req, res, key);
    return;
  }

  send(res, 404);
}

export function createServer(store: KvStore = new KvStore()): http.Server {
  const server = http.createServer((req, res) => {
    // Every response closes the connection; any unread body is discarded.
    res.shouldKeepAlive = false;
    route(store, req, res).catch((err: unknown) => {
      if (res.headersSent) {
        res.destroy();
        return;
      }
      send(res, err instanceof PayloadTooLargeError ? 413 : 500);
    });
  });
  server.on('clientError', (_err, socket) => {
    if (socket.writable) {
      socket.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
    } else {
      socket.destroy();
    }
  });
  return server;
}
