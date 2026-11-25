import { createServer } from 'node:http';
import { Store } from './store.js';

export const MAX_VALUE_BYTES = 1024 * 1024;
const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/;

class HttpError extends Error {
  constructor(status) {
    super(`HTTP ${status}`);
    this.status = status;
  }
}

function send(res, status, body = '', contentType = 'text/plain; charset=utf-8') {
  const payload = typeof body === 'string' ? Buffer.from(body) : body;
  const headers = { 'Content-Length': payload.length };
  if (payload.length > 0) headers['Content-Type'] = contentType;
  res.writeHead(status, headers);
  res.end(payload);
}

async function readBody(req) {
  const declared = Number(req.headers['content-length'] ?? 0);
  if (declared > MAX_VALUE_BYTES) throw new HttpError(413);
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_VALUE_BYTES) throw new HttpError(413);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

function methodNotAllowed(res, allowed) {
  res.setHeader('Allow', allowed.join(', '));
  send(res, 405);
}

async function handleKey(store, req, res, key) {
  if (!KEY_RE.test(key)) return send(res, 400);
  switch (req.method) {
    case 'GET': {
      const value = store.get(key);
      return value === undefined ? send(res, 404) : send(res, 200, value, 'application/octet-stream');
    }
    case 'PUT': {
      const value = await readBody(req);
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
    return req.method === 'GET' ? send(res, 200, 'ok') : methodNotAllowed(res, ['GET']);
  }
  if (path === '/kv') {
    return req.method === 'GET'
      ? send(res, 200, JSON.stringify(store.keys()), 'application/json')
      : methodNotAllowed(res, ['GET']);
  }
  if (path.startsWith('/kv/')) return handleKey(store, req, res, path.slice('/kv/'.length));
  return send(res, 404);
}

export function createApp(store = new Store()) {
  return createServer({ keepAlive: false }, async (req, res) => {
    try {
      await route(store, req, res);
    } catch (err) {
      const status = err instanceof HttpError ? err.status : 500;
      if (status === 500) console.error(err);
      if (res.headersSent) return res.destroy();
      res.setHeader('Connection', 'close');
      send(res, status);
      // Stop reading an oversized or broken request body.
      res.on('finish', () => req.destroy());
    }
  });
}
