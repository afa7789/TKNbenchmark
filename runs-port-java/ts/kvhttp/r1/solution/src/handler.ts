import type { IncomingMessage, RequestListener, ServerResponse } from 'node:http';
import type { KvStore } from './store.ts';

export const MAX_VALUE_BYTES = 1 << 20;

const KEY = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

interface Response {
  readonly status: number;
  readonly contentType?: string;
  readonly body?: Buffer;
}

class PayloadTooLargeError extends Error {
  constructor() {
    super('payload too large');
    this.name = 'PayloadTooLargeError';
  }
}

const status = (code: number): Response => ({ status: code });

const text = (code: number, body: string): Response => ({
  status: code,
  contentType: 'text/plain; charset=utf-8',
  body: Buffer.from(body, 'utf8'),
});

/** Builds the request listener that routes and serves the key-value HTTP API. */
export function createHandler(store: KvStore): RequestListener {
  async function route(req: IncomingMessage): Promise<Response> {
    const method = req.method ?? '';
    const path = rawPath(req.url ?? '');

    if (path === '/health') {
      return method === 'GET' ? text(200, 'ok') : status(405);
    }
    if (path === '/kv') {
      return method === 'GET' ? listKeys() : status(405);
    }
    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length);
      if (!KEY.test(key)) {
        return status(400);
      }
      switch (method) {
        case 'GET': {
          const value = store.get(key);
          return value ? { status: 200, contentType: 'application/octet-stream', body: value } : status(404);
        }
        case 'PUT':
          return status(store.put(key, await readBody(req)) ? 201 : 200);
        case 'DELETE':
          return status(store.delete(key) ? 204 : 404);
        default:
          return status(405);
      }
    }
    return status(404);
  }

  function listKeys(): Response {
    // Keys are restricted to [A-Za-z0-9_-], so JSON.stringify needs no escaping beyond quoting.
    return {
      status: 200,
      contentType: 'application/json',
      body: Buffer.from(JSON.stringify(store.keys()), 'utf8'),
    };
  }

  return (req, res) => {
    route(req).then(
      (response) => send(req, res, response),
      (err: unknown) => {
        if (err instanceof PayloadTooLargeError) {
          // The rest of the body is never read, so the connection cannot be reused.
          res.shouldKeepAlive = false;
          send(req, res, status(413));
          return;
        }
        console.error('Unhandled error serving request', err);
        send(req, res, status(500));
      },
    );
  };
}

/** Returns the path component of a request target, without any query string or fragment. */
function rawPath(target: string): string {
  const end = target.search(/[?#]/);
  return end === -1 ? target : target.slice(0, end);
}

async function readBody(req: IncomingMessage): Promise<Buffer> {
  const declared = req.headers['content-length'];
  if (declared !== undefined && Number(declared) > MAX_VALUE_BYTES) {
    throw new PayloadTooLargeError();
  }
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > MAX_VALUE_BYTES) {
      throw new PayloadTooLargeError();
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

function send(req: IncomingMessage, res: ServerResponse, response: Response): void {
  if (res.headersSent || res.destroyed) {
    return;
  }
  const headers: Record<string, string | number> = {};
  if (response.contentType !== undefined) {
    headers['Content-Type'] = response.contentType;
  }
  const bodyForbidden = response.status === 204 || response.status === 304 || req.method === 'HEAD';
  const body = bodyForbidden ? undefined : response.body;
  if (response.status !== 204) {
    headers['Content-Length'] = body?.length ?? 0;
  }
  res.writeHead(response.status, headers);
  res.end(body);
}
