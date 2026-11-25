import { test } from 'node:test';
import { once } from 'node:events';
import { createKvServer } from '../src/server.js';

async function start(t) {
  const server = createKvServer().listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  return (path, init) => fetch(base + path, init);
}

test('crud and listing', async (t) => {
  const req = await start(t);
  t.assert.equal((await req('/health')).status, 200);
  t.assert.equal((await req('/kv/b', { method: 'PUT', body: 'x' })).status, 201);
  t.assert.equal((await req('/kv/a', { method: 'PUT', body: new Uint8Array([0, 255]) })).status, 201);
  t.assert.equal((await req('/kv/a', { method: 'PUT', body: new Uint8Array([1, 254]) })).status, 200);
  t.assert.deepStrictEqual([...new Uint8Array(await (await req('/kv/a')).arrayBuffer())], [1, 254]);
  t.assert.deepStrictEqual(await (await req('/kv')).json(), ['a', 'b']);
  t.assert.equal((await req('/kv/a', { method: 'DELETE' })).status, 204);
  t.assert.equal((await req('/kv/a', { method: 'DELETE' })).status, 404);
  t.assert.equal((await req('/kv/a')).status, 404);
});

test('errors', async (t) => {
  const req = await start(t);
  t.assert.equal((await req('/nope')).status, 404);
  t.assert.equal((await req('/health', { method: 'POST' })).status, 405);
  t.assert.equal((await req('/kv', { method: 'DELETE' })).status, 405);
  t.assert.equal((await req('/kv/a', { method: 'PATCH' })).status, 405);
  for (const p of ['/kv/', '/kv/a/b', '/kv/bad.key', `/kv/${'x'.repeat(65)}`]) {
    t.assert.equal((await req(p)).status, 400, p);
  }
  t.assert.equal((await req(`/kv/${'x'.repeat(64)}`)).status, 404);
});
