import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { KvStore } from './store.ts';

export const MAX_VALUE_BYTES = 1024 * 1024;
const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

class HttpError extends Error {
  readonly status: number;
  constructor(status: number) {
    super(`HTTP ${status}`);
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
  if (contentType !== undefined) res.setHeader('Content-Type', contentType);
  if (status !== 204) res.setHeader('Content-Length', payload.length);
  res.writeHead(status);
  res.end(status === 204 ? undefined : payload);
}

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

type Handler = (req: IncomingMessage, res: ServerResponse) => Promise<void>;

export function createKvServer(store: KvStore = new KvStore()): Server {
  const handleKey = async (req: IncomingMessage, res: ServerResponse, key: string): Promise<void> => {
    switch (req.method) {
      case 'GET': {
        const value = store.get(key);
        if (value === undefined) send(res, 404);
        else send(res, 200, value, 'application/octet-stream');
        return;
      }
      case 'PUT': {
        const body = await readBody(req);
        send(res, store.put(key, body) ? 201 : 200);
        return;
      }
      case 'DELETE':
        send(res, store.delete(key) ? 204 : 404);
        return;
      default:
        send(res, 405);
    }
  };

  const route: Handler = async (req, res) => {
    const path = req.url ?? '/';
    if (path === '/health') {
      if (req.method === 'GET') send(res, 200, 'ok', 'text/plain');
      else send(res, 405);
      return;
    }
    if (path === '/kv') {
      if (req.method === 'GET') send(res, 200, JSON.stringify(store.keys()), 'application/json');
      else send(res, 405);
      return;
    }
    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length);
      if (!KEY_PATTERN.test(key)) {
        send(res, 400);
        return;
      }
      await handleKey(req, res, key);
      return;
    }
    send(res, 404);
  };

  return createServer({ keepAlive: false }, (req, res) => {
    route(req, res).catch((err: unknown) => {
      const status = err instanceof HttpError ? err.status : 500;
      if (!res.headersSent) {
        res.setHeader('Connection', 'close');
        send(res, status);
      } else {
        res.destroy();
      }
    });
  });
}
