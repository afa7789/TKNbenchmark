import assert from 'node:assert/strict';
import { test } from 'node:test';
import { makeHandler, type Request } from '../src/handler.ts';
import { Store } from '../src/store.ts';

const call = (h: ReturnType<typeof makeHandler>, method: string, path: string, body?: string) =>
  h({ method, path, body: Buffer.from(body ?? '') } satisfies Request);

test('crud', () => {
  const h = makeHandler(new Store());
  assert.equal(call(h, 'PUT', '/kv/a', 'hello').status, 201);
  assert.equal(call(h, 'GET', '/kv/a').body.toString(), 'hello');
  assert.equal(call(h, 'PUT', '/kv/a', 'world').status, 200);
  assert.equal(call(h, 'GET', '/kv/a').body.toString(), 'world');
  assert.equal(call(h, 'DELETE', '/kv/a').status, 204);
  assert.equal(call(h, 'GET', '/kv/a').status, 404);
  assert.equal(call(h, 'DELETE', '/kv/a').status, 404);
});

test('listing', () => {
  const h = makeHandler(new Store());
  for (const k of ['b', 'a', 'c']) call(h, 'PUT', `/kv/${k}`, k);
  const res = call(h, 'GET', '/kv');
  assert.equal(res.status, 200);
  assert.equal(res.headers['Content-Type'], 'application/json');
  assert.equal(res.body.toString(), '["a","b","c"]');
});

test('errors', () => {
  const h = makeHandler(new Store());
  for (const path of ['/kv/', '/kv/a/b', '/kv/bad.key', `/kv/${'a'.repeat(65)}`]) {
    assert.equal(call(h, 'GET', path).status, 400, path);
  }
  for (const path of ['/', '/nope', '/health/', '/kvx']) {
    assert.equal(call(h, 'GET', path).status, 404, path);
  }
  assert.equal(call(h, 'POST', '/health').status, 405);
  assert.equal(call(h, 'PUT', '/kv').status, 405);
  assert.equal(call(h, 'PATCH', '/kv/a').status, 405);
});
