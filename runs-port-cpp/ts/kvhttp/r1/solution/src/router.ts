import { emptyResponse, textResponse, type Request, type Response } from './http.ts';
import type { KvStore } from './kvStore.ts';

const KV_PREFIX = '/kv/';
const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

function methodNotAllowed(allow: string): Response {
  return emptyResponse(405, [['Allow', allow]]);
}

/** Maps requests onto the key/value API described in SPEC.md. */
export class Router {
  readonly #store: KvStore;

  constructor(store: KvStore) {
    this.#store = store;
  }

  handle(request: Request): Response {
    const path = request.target;

    if (path === '/health') {
      return request.method === 'GET' ? textResponse(200, 'ok') : methodNotAllowed('GET');
    }
    if (path === '/kv') {
      return request.method === 'GET' ? this.#listKeys() : methodNotAllowed('GET');
    }
    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length);
      if (!KEY_PATTERN.test(key)) return emptyResponse(400);
      return this.#handleKey(request, key);
    }
    return emptyResponse(404);
  }

  #handleKey(request: Request, key: string): Response {
    switch (request.method) {
      case 'GET': {
        const value = this.#store.get(key);
        if (value === undefined) return emptyResponse(404);
        return { status: 200, headers: [['Content-Type', 'application/octet-stream']], body: value };
      }
      case 'PUT':
        return emptyResponse(this.#store.put(key, request.body) ? 201 : 200);
      case 'DELETE':
        return emptyResponse(this.#store.delete(key) ? 204 : 404);
      default:
        return methodNotAllowed('GET, PUT, DELETE');
    }
  }

  #listKeys(): Response {
    return textResponse(200, JSON.stringify(this.#store.keys()), 'application/json');
  }
}
