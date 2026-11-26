import { Store } from './store.ts';

export const MAX_VALUE_BYTES = 1024 * 1024;

const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/;
const KEY_PREFIX = '/kv/';

export interface Request {
  readonly method: string;
  readonly path: string;
  readonly body: Buffer;
}

export interface Response {
  readonly status: number;
  readonly body?: Buffer;
  readonly headers?: Readonly<Record<string, string>>;
}

const methodNotAllowed = (allow: string): Response => ({ status: 405, headers: { Allow: allow } });

/** Pure request router: maps a parsed request to a response. */
export class App {
  readonly store: Store;

  constructor(store: Store = new Store()) {
    this.store = store;
  }

  handle(req: Request): Response {
    const { method, path } = req;
    if (path === '/health') {
      if (method !== 'GET') return methodNotAllowed('GET');
      return {
        status: 200,
        body: Buffer.from('ok'),
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      };
    }
    if (path === '/kv') {
      if (method !== 'GET') return methodNotAllowed('GET');
      return {
        status: 200,
        body: Buffer.from(JSON.stringify(this.store.keys())),
        headers: { 'Content-Type': 'application/json' },
      };
    }
    if (path.startsWith(KEY_PREFIX)) {
      const key = path.slice(KEY_PREFIX.length);
      if (!KEY_RE.test(key)) return { status: 400 };
      return this.#handleKey(req, key);
    }
    return { status: 404 };
  }

  #handleKey(req: Request, key: string): Response {
    switch (req.method) {
      case 'GET': {
        const value = this.store.get(key);
        if (value === undefined) return { status: 404 };
        return { status: 200, body: value, headers: { 'Content-Type': 'application/octet-stream' } };
      }
      case 'PUT':
        return { status: this.store.put(key, req.body) ? 201 : 200 };
      case 'DELETE':
        return { status: this.store.delete(key) ? 204 : 404 };
      default:
        return methodNotAllowed('GET, PUT, DELETE');
    }
  }
}
