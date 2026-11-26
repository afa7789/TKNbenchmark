import type { Request, Response } from './http.ts';
import type { Store } from './store.ts';

const KV_PREFIX = '/kv/';
const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

const statusOnly = (status: number): Response => ({ status });

/** True if `key` matches [A-Za-z0-9_-]{1,64}. */
export function isValidKey(key: string): boolean {
  return KEY_PATTERN.test(key);
}

/** Maps requests onto the key/value API. */
export class Router {
  readonly #store: Store;

  constructor(store: Store) {
    this.#store = store;
  }

  handle(request: Request): Response {
    const path = request.target;

    if (path === '/health') {
      if (request.method !== 'GET') return statusOnly(405);
      return { status: 200, contentType: 'text/plain', body: Buffer.from('ok') };
    }

    if (path === '/kv') {
      if (request.method !== 'GET') return statusOnly(405);
      // Keys are restricted to [A-Za-z0-9_-], so JSON.stringify never needs to escape.
      return {
        status: 200,
        contentType: 'application/json',
        body: Buffer.from(JSON.stringify(this.#store.keys())),
      };
    }

    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length);
      if (!isValidKey(key)) return statusOnly(400);
      return this.#handleKey(request, key);
    }

    return statusOnly(404);
  }

  #handleKey(request: Request, key: string): Response {
    switch (request.method) {
      case 'GET': {
        const value = this.#store.get(key);
        if (value === undefined) return statusOnly(404);
        return { status: 200, contentType: 'application/octet-stream', body: value };
      }
      case 'PUT':
        return statusOnly(this.#store.put(key, request.body) ? 201 : 200);
      case 'DELETE':
        return statusOnly(this.#store.delete(key) ? 204 : 404);
      default:
        return statusOnly(405);
    }
  }
}
