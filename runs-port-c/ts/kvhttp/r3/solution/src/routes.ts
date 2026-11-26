import type { KvStore } from './store.ts';

export const MAX_KEY_LENGTH = 64;
export const MAX_VALUE_LENGTH = 1024 * 1024;

const KEY_PATTERN = new RegExp(`^[A-Za-z0-9_-]{1,${MAX_KEY_LENGTH}}$`);
const KV_PREFIX = '/kv/';

export interface Response {
  status: number;
  contentType?: string;
  body?: Buffer | string;
}

export interface Request {
  method: string;
  path: string;
  body: Buffer;
}

const status = (code: number): Response => ({ status: code });

export function isValidKey(key: string): boolean {
  return KEY_PATTERN.test(key);
}

function handleKey(store: KvStore, method: string, key: string, body: Buffer): Response {
  switch (method) {
    case 'GET': {
      const value = store.get(key);
      return value === undefined
        ? status(404)
        : { status: 200, contentType: 'application/octet-stream', body: value };
    }
    case 'PUT':
      return status(store.put(key, body) ? 201 : 200);
    case 'DELETE':
      return status(store.delete(key) ? 204 : 404);
    default:
      return status(405);
  }
}

/** Maps a fully received request to its response. */
export function route(store: KvStore, { method, path, body }: Request): Response {
  if (path === '/health') {
    return method === 'GET' ? { status: 200, contentType: 'text/plain', body: 'ok' } : status(405);
  }
  if (path === '/kv') {
    return method === 'GET'
      ? { status: 200, contentType: 'application/json', body: JSON.stringify(store.sortedKeys()) }
      : status(405);
  }
  if (path.startsWith(KV_PREFIX)) {
    const key = path.slice(KV_PREFIX.length);
    return isValidKey(key) ? handleKey(store, method, key, body) : status(400);
  }
  return status(404);
}
