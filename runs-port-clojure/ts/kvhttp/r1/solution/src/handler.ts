import type { Store } from './store.ts';

export interface Request {
  method: string;
  /** Request path without the query string. */
  path: string;
  body: Buffer;
}

export interface Response {
  status: number;
  headers: Record<string, string>;
  body: Buffer;
}

const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const EMPTY = Buffer.alloc(0);

const respond = (status: number, body: Buffer = EMPTY, headers: Record<string, string> = {}): Response => ({
  status,
  headers,
  body,
});

const methodNotAllowed = (allowed: string): Response => respond(405, EMPTY, { Allow: allowed });

function health({ method }: Request): Response {
  if (method !== 'GET') return methodNotAllowed('GET');
  return respond(200, Buffer.from('ok'), { 'Content-Type': 'text/plain; charset=utf-8' });
}

function listKeys(store: Store, { method }: Request): Response {
  if (method !== 'GET') return methodNotAllowed('GET');
  return respond(200, Buffer.from(JSON.stringify(store.keys())), { 'Content-Type': 'application/json' });
}

function item(store: Store, key: string, { method, body }: Request): Response {
  if (!KEY_PATTERN.test(key)) return respond(400);
  switch (method) {
    case 'GET': {
      const value = store.lookup(key);
      return value === undefined ? respond(404) : respond(200, value, { 'Content-Type': 'application/octet-stream' });
    }
    case 'PUT':
      return respond(store.put(key, body) ? 201 : 200);
    case 'DELETE':
      return respond(store.delete(key) ? 204 : 404);
    default:
      return methodNotAllowed('GET, PUT, DELETE');
  }
}

/** Returns a request handler backed by `store`. */
export function makeHandler(store: Store): (req: Request) => Response {
  return (req) => {
    const { path } = req;
    if (path === '/health') return health(req);
    if (path === '/kv') return listKeys(store, req);
    if (path.startsWith('/kv/')) return item(store, path.slice(4), req);
    return respond(404);
  };
}
