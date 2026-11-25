import { createServer } from 'node:http';
import { Store } from './store.js';

export const MAX_VALUE_BYTES = 1024 * 1024;
const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = '/kv/';

class HttpError extends Error {
  constructor(status) {
    super(`HTTP ${status}`);
    this.status = status;
  }
}

function send(res, status, body = '', headers = {}) {
  const payload = typeof body === 'string' ? Buffer.from(body) : body;
  res.writeHead(status, { ...headers, 'Content-Length': payload.length });
  res.end(payload);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'] ?? 0);
    if (declared > MAX_VALUE_BYTES) {
      reject(new HttpError(413));
      return;
    }
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_VALUE_BYTES) {
        req.removeAllListeners('data');
        reject(new HttpError(413));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks, size)));
    req.on('error', reject);
  });
}

function methodNotAllowed(res, allowed) {
  send(res, 405, '', { Allow: allowed.join(', ') });
}

async function handleKey(store, req, res, key) {
  switch (req.method) {
    case 'GET': {
      const value = store.get(key);
      if (value === undefined) send(res, 404);
      else send(res, 200, value, { 'Content-Type': 'application/octet-stream' });
      return;
    }
    case 'PUT': {
      const value = await readBody(req);
      send(res, store.set(key, value) ? 201 : 200);
      return;
    }
    case 'DELETE':
      send(res, store.delete(key) ? 204 : 404);
      return;
    default:
      methodNotAllowed(res, ['GET', 'PUT', 'DELETE']);
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
      if (res.headersSent) {
        res.destroy();
        return;
      }
      const status = err instanceof HttpError ? err.status : 500;
      res.setHeader('Connection', 'close');
      send(res, status);
    });
  });
  server.on('clientError', (err, socket) => {
    if (socket.writable && !socket.writableEnded) {
      socket.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
    } else {
      socket.destroy();
    }
  });
  return server;
}
