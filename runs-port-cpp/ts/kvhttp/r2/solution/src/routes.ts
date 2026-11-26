import { emptyResponse, textResponse, type Request, type Response } from './http.ts';
import type { KvStore } from './kvStore.ts';

const KV_PREFIX = '/kv/';
const KEY_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export const isValidKey = (key: string): boolean => KEY_PATTERN.test(key);

const methodNotAllowed = (allow: string): Response => ({
  ...textResponse(405, 'Method Not Allowed'),
  headers: { 'Content-Type': 'text/plain; charset=utf-8', Allow: allow },
});

const notFound = (): Response => textResponse(404, 'not found');

function handleHealth(request: Request): Response {
  return request.method === 'GET' ? textResponse(200, 'ok') : methodNotAllowed('GET');
}

function handleList(store: KvStore, request: Request): Response {
  if (request.method !== 'GET') return methodNotAllowed('GET');
  return {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(store.keys()),
  };
}

function handleKey(store: KvStore, request: Request, key: string): Response {
  if (!isValidKey(key)) return textResponse(400, 'invalid key');

  switch (request.method) {
    case 'GET': {
      const value = store.get(key);
      return value
        ? { status: 200, headers: { 'Content-Type': 'application/octet-stream' }, body: value }
        : notFound();
    }
    case 'PUT':
      return emptyResponse(store.put(key, request.body) === 'created' ? 201 : 200);
    case 'DELETE':
      return store.delete(key) ? emptyResponse(204) : notFound();
    default:
      return methodNotAllowed('GET, PUT, DELETE');
  }
}

/** Dispatches a request to the matching route. */
export function route(store: KvStore, request: Request): Response {
  const { path } = request;
  if (path === '/health') return handleHealth(request);
  if (path === '/kv') return handleList(store, request);
  if (path.startsWith(KV_PREFIX)) return handleKey(store, request, path.slice(KV_PREFIX.length));
  return notFound();
}
