import http, { type IncomingMessage, type ServerResponse } from 'node:http';
import { KvStore } from './store.ts';

export const MAX_VALUE_BYTES = 1 << 20;
const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

interface Reply {
  status: number;
  body?: Buffer | string;
  contentType?: string;
  allow?: string;
}

class HttpError extends Error {
  readonly status: number;

  constructor(status: number) {
    super(http.STATUS_CODES[status] ?? `HTTP ${status}`);
    this.status = status;
  }
}

function send(res: ServerResponse, { status, body, contentType, allow }: Reply): void {
  const payload = body === undefined ? Buffer.alloc(0) : Buffer.from(body);
  const headers: http.OutgoingHttpHeaders = {
    'Content-Length': payload.length,
    Connection: 'close',
  };
  if (contentType) headers['Content-Type'] = contentType;
  if (allow) headers.Allow = allow;
  res.writeHead(status, headers);
  res.end(payload);
}

const methodNotAllowed = (allow: string): Reply => ({ status: 405, allow });

/** Reads the full request body, enforcing the value size limit. */
async function readBody(req: IncomingMessage): Promise<Buffer> {
  const declared = Number(req.headers['content-length'] ?? 0);
  if (declared > MAX_VALUE_BYTES) throw new HttpError(413);

  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > MAX_VALUE_BYTES) throw new HttpError(413);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

async function route(store: KvStore, req: IncomingMessage): Promise<Reply> {
  const { method = '', url = '' } = req;

  if (url === '/health') {
    return method === 'GET'
      ? { status: 200, body: 'ok', contentType: 'text/plain; charset=utf-8' }
      : methodNotAllowed('GET');
  }

  if (url === '/kv') {
    return method === 'GET'
      ? { status: 200, body: JSON.stringify(store.keys()), contentType: 'application/json' }
      : methodNotAllowed('GET');
  }

  if (url.startsWith(KV_PREFIX)) {
    const key = url.slice(KV_PREFIX.length);
    if (!KEY_PATTERN.test(key)) return { status: 400 };

    switch (method) {
      case 'GET': {
        const value = store.get(key);
        return value === undefined
          ? { status: 404 }
          : { status: 200, body: value, contentType: 'application/octet-stream' };
      }
      case 'PUT': {
        const value = await readBody(req);
        return { status: store.put(key, value) ? 201 : 200 };
      }
      case 'DELETE':
        return { status: store.delete(key) ? 204 : 404 };
      default:
        return methodNotAllowed('GET, PUT, DELETE');
    }
  }

  return { status: 404 };
}

export function createKvServer(store = new KvStore()): http.Server {
  const server = http.createServer(async (req, res) => {
    let reply: Reply;
    try {
      reply = await route(store, req);
    } catch (err) {
      if (req.destroyed && !(err instanceof HttpError)) return; // client went away
      reply = { status: err instanceof HttpError ? err.status : 500 };
    }
    // Discard any unread request body so the client can read the reply cleanly.
    if (!req.complete) req.resume();
    send(res, reply);
  });

  server.headersTimeout = 10_000;
  server.requestTimeout = 30_000;
  server.on('clientError', (err: NodeJS.ErrnoException, socket) => {
    if (!socket.writable) return socket.destroy();
    const status = err.code === 'HPE_HEADER_OVERFLOW' ? 431 : 400;
    socket.end(`HTTP/1.1 ${status} ${http.STATUS_CODES[status]}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n`);
  });
  return server;
}
