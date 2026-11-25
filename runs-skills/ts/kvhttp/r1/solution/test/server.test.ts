import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import { createServer, MAX_VALUE_BYTES } from '../src/server.ts';

const server = createServer();
let base = '';

before(async () => {
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => {
  server.closeAllConnections();
  server.close();
});

const req = (method: string, path: string, body?: Uint8Array<ArrayBuffer> | string) =>
  fetch(base + path, { method, ...(body === undefined ? {} : { body }) });

describe('kvhttp', () => {
  it('health', async () => {
    const res = await req('GET', '/health');
    assert.equal(res.status, 200);
    assert.equal(await res.text(), 'ok');
    assert.equal((await req('POST', '/health')).status, 405);
  });

  it('crud with binary values', async () => {
    const bytes = new Uint8Array([0, 255, 10, 13, 200]);
    assert.equal((await req('PUT', '/kv/bin', bytes)).status, 201);
    assert.equal((await req('PUT', '/kv/bin', bytes)).status, 200);
    const got = await req('GET', '/kv/bin');
    assert.deepEqual(new Uint8Array(await got.arrayBuffer()), bytes);
    assert.equal((await req('DELETE', '/kv/bin')).status, 204);
    assert.equal((await req('DELETE', '/kv/bin')).status, 404);
    assert.equal((await req('GET', '/kv/bin')).status, 404);
  });

  it('empty and max-size values', async () => {
    assert.equal((await req('PUT', '/kv/empty', '')).status, 201);
    assert.equal(await (await req('GET', '/kv/empty')).text(), '');
    const big = new Uint8Array(MAX_VALUE_BYTES).fill(7);
    assert.equal((await req('PUT', '/kv/big', big)).status, 201);
    assert.equal((await (await req('GET', '/kv/big')).arrayBuffer()).byteLength, MAX_VALUE_BYTES);
  });

  it('lists keys sorted', async () => {
    await req('PUT', '/kv/Z', '1');
    await req('PUT', '/kv/a', '1');
    const res = await req('GET', '/kv');
    assert.match(res.headers.get('content-type') ?? '', /application\/json/);
    const keys = (await res.json()) as string[];
    assert.deepEqual(keys, [...keys].sort());
    assert.equal((await req('DELETE', '/kv')).status, 405);
  });

  it('errors', async () => {
    for (const p of ['/kv/', '/kv/a.b', '/kv/a/b', `/kv/${'x'.repeat(65)}`, '/kv/%41'])
      assert.equal((await req('GET', p)).status, 400, p);
    assert.equal((await req('GET', `/kv/${'x'.repeat(64)}`)).status, 404);
    assert.equal((await req('GET', '/nope')).status, 404);
    assert.equal((await req('GET', '/health/')).status, 404);
    assert.equal((await req('PATCH', '/kv/a')).status, 405);
  });
});
