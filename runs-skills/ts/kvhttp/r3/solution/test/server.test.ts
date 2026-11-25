import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import { createKvServer, MAX_VALUE_BYTES } from '../src/server.ts';

const server = createKvServer();
let base = '';

before(async () => {
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => server.close());

const req = (method: string, path: string, body?: Uint8Array<ArrayBuffer>) =>
  fetch(base + path, { method, ...(body ? { body } : {}), headers: { connection: 'close' } });

describe('kv server', () => {
  it('serves health', async () => {
    const res = await req('GET', '/health');
    assert.equal(res.status, 200);
    assert.equal(await res.text(), 'ok');
    assert.equal((await req('POST', '/health')).status, 405);
  });

  it('round-trips binary values', async () => {
    const value = new Uint8Array([0, 255, 13, 10, 200]);
    assert.equal((await req('PUT', '/kv/bin', value)).status, 201);
    assert.equal((await req('PUT', '/kv/bin', value)).status, 200);
    const res = await req('GET', '/kv/bin');
    assert.deepEqual(new Uint8Array(await res.arrayBuffer()), value);
    assert.equal((await req('DELETE', '/kv/bin')).status, 204);
    assert.equal((await req('DELETE', '/kv/bin')).status, 404);
  });

  it('lists keys sorted', async () => {
    for (const k of ['b', 'A', 'a']) await req('PUT', `/kv/${k}`, new Uint8Array([1]));
    const res = await req('GET', '/kv');
    assert.match(res.headers.get('content-type') ?? '', /application\/json/);
    assert.deepEqual(await res.json(), ['A', 'a', 'b']);
  });

  it('validates keys and routes', async () => {
    for (const p of ['/kv/', '/kv/a/b', '/kv/a.b', `/kv/${'x'.repeat(65)}`]) {
      assert.equal((await req('GET', p)).status, 400, p);
    }
    assert.equal((await req('GET', `/kv/${'x'.repeat(64)}`)).status, 404);
    assert.equal((await req('GET', '/other')).status, 404);
    assert.equal((await req('PATCH', '/kv/a')).status, 405);
    assert.equal((await req('POST', '/kv')).status, 405);
  });

  it('accepts a 1 MiB value and rejects larger', async () => {
    assert.equal((await req('PUT', '/kv/big', new Uint8Array(MAX_VALUE_BYTES))).status, 201);
    assert.equal((await req('PUT', '/kv/big2', new Uint8Array(MAX_VALUE_BYTES + 1))).status, 413);
  });
});
