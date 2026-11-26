/** HTTP routing for the key-value API. */
import http, { type IncomingMessage, type ServerResponse } from 'node:http';
import { isValidKey, type Store } from './store.ts';

export const MAX_VALUE_BYTES = 1024 * 1024;
const MAX_HEADER_BYTES = 16 * 1024;
/** Oversized bodies are drained (so closing does not reset the connection) up to this limit. */
const MAX_DRAIN_BYTES = 4 * MAX_VALUE_BYTES;
const REQUEST_TIMEOUT_MS = 30_000;

class HttpError extends Error {
  readonly status: number;
  constructor(status: number) {
    super(http.STATUS_CODES[status] ?? `HTTP ${status}`);
    this.status = status;
  }
}

function send(
  res: ServerResponse,
  status: number,
  body?: Buffer | string,
  contentType?: string,
): void {
  const payload = body === undefined ? Buffer.alloc(0) : Buffer.from(body);
  const headers: http.OutgoingHttpHeaders = {
    'Content-Length': payload.length,
    Connection: 'close',
  };
  if (contentType !== undefined) headers['Content-Type'] = contentType;
  res.writeHead(status, headers);
  res.end(payload);
}

/**
 * Reads the request body, enforcing the value size limit. An oversized body is
 * still consumed (up to a bound) before rejecting, so the 413 reaches the client.
 */
function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'] ?? 0);
    const chunks: Buffer[] = [];
    let received = 0;
    let tooLarge = declared > limit;

    if (declared > MAX_DRAIN_BYTES) {
      reject(new HttpError(413));
      return;
    }

    req.on('data', (chunk: Buffer) => {
      received += chunk.length;
      if (received > limit) tooLarge = true;
      if (tooLarge) {
        chunks.length = 0;
        if (received > MAX_DRAIN_BYTES) {
          req.removeAllListeners('data');
          req.pause();
          reject(new HttpError(413));
        }
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (tooLarge) reject(new HttpError(413));
      else resolve(Buffer.concat(chunks, received));
    });
    req.on('error', reject);
  });
}

async function handleKey(
  store: Store,
  req: IncomingMessage,
  res: ServerResponse,
  key: string,
): Promise<void> {
  switch (req.method) {
    case 'GET': {
      const value = store.get(key);
      if (value === undefined) send(res, 404);
      else send(res, 200, value, 'application/octet-stream');
      return;
    }
    case 'PUT': {
      const body = await readBody(req, MAX_VALUE_BYTES);
      send(res, store.put(key, body) === 'created' ? 201 : 200);
      return;
    }
    case 'DELETE':
      send(res, store.delete(key) ? 204 : 404);
      return;
    default:
      send(res, 405);
  }
}

type Route =
  | { kind: 'health' }
  | { kind: 'list' }
  | { kind: 'key'; key: string }
  | { kind: 'invalid-key' }
  | { kind: 'not-found' };

function resolveRoute(path: string): Route {
  if (path === '/health') return { kind: 'health' };
  if (path === '/kv') return { kind: 'list' };
  if (path.startsWith('/kv/')) {
    const key = path.slice('/kv/'.length);
    return isValidKey(key) ? { kind: 'key', key } : { kind: 'invalid-key' };
  }
  return { kind: 'not-found' };
}

async function route(store: Store, req: IncomingMessage, res: ServerResponse): Promise<void> {
  const target = resolveRoute(req.url ?? '');
  switch (target.kind) {
    case 'health':
      if (req.method === 'GET') send(res, 200, 'ok', 'text/plain');
      else send(res, 405);
      return;
    case 'list':
      // Keys are restricted to [A-Za-z0-9_-], so the JSON needs no special escaping.
      if (req.method === 'GET') send(res, 200, JSON.stringify(store.keys()), 'application/json');
      else send(res, 405);
      return;
    case 'key':
      await handleKey(store, req, res, target.key);
      return;
    case 'invalid-key':
      send(res, 400);
      return;
    case 'not-found':
      send(res, 404);
      return;
  }
}

const REQUEST_LINE = /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+ (\S+) HTTP\/1\.\d\r?\n/;

/**
 * Status for a request Node's parser refused. llhttp only knows registered
 * method names, so an unknown-but-well-formed method lands here; answer it the
 * way a known route would (405), keeping 400 for genuinely malformed input.
 */
function clientErrorStatus(err: NodeJS.ErrnoException & { rawPacket?: Buffer }): number {
  if (err.code === 'HPE_HEADER_OVERFLOW') return 431;
  if (err.code === 'HPE_INVALID_METHOD' && err.rawPacket) {
    const match = REQUEST_LINE.exec(err.rawPacket.toString('latin1'));
    if (match?.[1] !== undefined) {
      switch (resolveRoute(match[1]).kind) {
        case 'invalid-key':
          return 400;
        case 'not-found':
          return 404;
        default:
          return 405;
      }
    }
  }
  return 400;
}

export function createServer(store: Store): http.Server {
  const server = http.createServer(
    {
      maxHeaderSize: MAX_HEADER_BYTES,
      requestTimeout: REQUEST_TIMEOUT_MS,
      keepAlive: false,
    },
    (req, res) => {
      route(store, req, res).catch((err: unknown) => {
        if (res.headersSent) {
          res.destroy();
          return;
        }
        send(res, err instanceof HttpError ? err.status : 500);
      });
    },
  );
  server.on('clientError', (err: NodeJS.ErrnoException & { rawPacket?: Buffer }, socket) => {
    if (!socket.writable || socket.writableEnded) {
      socket.destroy();
      return;
    }
    const status = clientErrorStatus(err);
    const reason = http.STATUS_CODES[status] ?? '';
    socket.end(`HTTP/1.1 ${status} ${reason}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n`);
  });
  return server;
}
