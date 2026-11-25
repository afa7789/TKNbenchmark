import { createServer } from 'node:http';
import { Store } from './store.js';

export const MAX_VALUE_BYTES = 1024 * 1024;
const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

class HttpError extends Error {
  constructor(status) {
    super(String(status));
    this.status = status;
  }
}

function send(res, status, body = '', headers = {}) {
  const buf = typeof body === 'string' ? Buffer.from(body) : body;
  res.writeHead(status, { ...headers, 'Content-Length': buf.length });
  res.end(buf);
}

function methodNotAllowed(res, allowed) {
  send(res, 405, '', { Allow: allowed.join(', ') });
}

/** Reads the full request body, rejecting with 413 past the size limit. */
async function readBody(req, limit) {
  const declared = Number(req.headers['content-length']);
  if (Number.isFinite(declared) && declared > limit) throw new HttpError(413);
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw new HttpError(413);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

async function handleKey(store, req, res, key) {
  switch (req.method) {
    case 'GET': {
      const value = store.get(key);
      if (value === undefined) return send(res, 404);
      return send(res, 200, value, { 'Content-Type': 'application/octet-stream' });
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

async function route(store, req, res) {
  const path = req.url ?? '/';

  if (path === '/health') {
    if (req.method !== 'GET') return methodNotAllowed(res, ['GET']);
    return send(res, 200, 'ok', { 'Content-Type': 'text/plain' });
  }

  if (path === '/kv') {
    if (req.method !== 'GET') return methodNotAllowed(res, ['GET']);
    return send(res, 200, JSON.stringify(store.keys()), { 'Content-Type': 'application/json' });
  }

  if (path.startsWith(KV_PREFIX)) {
    const key = path.slice(KV_PREFIX.length);
    if (!KEY_RE.test(key)) return send(res, 400);
    return handleKey(store, req, res, key);
  }

  return send(res, 404);
}

export function createKvServer(store = new Store()) {
  const server = createServer({ keepAliveTimeout: 5000 }, (req, res) => {
    route(store, req, res).catch((err) => {
      const status = err instanceof HttpError ? err.status : 500;
      if (status === 500) console.error(err);
      if (res.headersSent) return res.destroy();
      // The unread remainder of the body makes the connection unusable; close it.
      send(res, status, '', { Connection: 'close' });
    });
  });
  return server;
}
