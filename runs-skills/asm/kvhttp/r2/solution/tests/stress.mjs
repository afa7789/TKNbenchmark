import http from 'node:http'
import { spawn } from 'node:child_process'
import crypto from 'node:crypto'
import assert from 'node:assert'
const port = 20000 + Math.floor(Math.random() * 40000)
const child = spawn('./app', [String(port)], { stdio: 'inherit' })
const req = (method, path, body) => new Promise((res, rej) => {
  const headers = { Connection: 'close' }
  if (body) headers['Content-Length'] = body.length
  const r = http.request({ host: '127.0.0.1', port, method, path, headers, agent: false }, (s) => {
    const c = []; s.on('data', (d) => c.push(d)); s.on('end', () => res({ status: s.statusCode, headers: s.headers, body: Buffer.concat(c) }))
  })
  r.on('error', rej); r.end(body)
})
await new Promise((r) => setTimeout(r, 200))
try {
  let r = await req('GET', '/health'); assert.equal(r.status, 200); assert.equal(r.body.toString(), 'ok')
  const big = crypto.randomBytes(1 << 20)
  r = await req('PUT', '/kv/big', big); assert.equal(r.status, 201)
  r = await req('GET', '/kv/big'); assert.equal(r.status, 200); assert.ok(r.body.equals(big))
  r = await req('PUT', '/kv/big', Buffer.alloc((1 << 20) + 1)); console.log('oversize ->', r.status)
  r = await req('PUT', '/kv/empty', Buffer.alloc(0)); assert.equal(r.status, 201)
  r = await req('PUT', '/kv/empty2'); assert.equal(r.status, 201)
  r = await req('GET', '/kv/empty'); assert.equal(r.status, 200); assert.equal(r.body.length, 0)
  const k64 = 'a'.repeat(64)
  r = await req('PUT', '/kv/' + k64, Buffer.from('x')); assert.equal(r.status, 201)
  r = await req('PUT', '/kv/' + k64 + 'a', Buffer.from('x')); assert.equal(r.status, 400)
  for (const p of ['/kv/', '/kv/a/b', '/kv/a%20', '/kv/a.b']) { r = await req('GET', p); assert.equal(r.status, 400, p) }
  for (const p of ['/', '/kvx', '/kv/../x'.slice(0,0) + '/healthz', '/health/', '/KV/a']) { r = await req('GET', p); assert.equal(r.status, 404, p) }
  for (const [m, p] of [['POST', '/kv'], ['DELETE', '/kv'], ['PUT', '/health'], ['POST', '/kv/a'], ['HEAD', '/kv/a']]) { r = await req(m, p); assert.equal(r.status, 405, m + p) }
  // parallel
  const keys = Array.from({ length: 500 }, (_, i) => 'k-' + crypto.randomBytes(6).toString('base64url'))
  for (let i = 0; i < keys.length; i += 100) {
    const rs = await Promise.all(keys.slice(i, i + 100).map((k) => req('PUT', '/kv/' + k, Buffer.from(k.repeat(100)))))
    rs.forEach((x) => assert.equal(x.status, 201))
  }
  const rs = await Promise.all(keys.slice(0, 100).map((k) => req('GET', '/kv/' + k)))
  rs.forEach((x, i) => assert.equal(x.body.toString(), keys[i].repeat(100)))
  r = await req('GET', '/kv'); assert.equal(r.headers['content-type'], 'application/json')
  const all = [...keys, 'big', 'empty', 'empty2', k64].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
  assert.deepEqual(JSON.parse(r.body), all)
  for (const k of keys.slice(0, 250)) { r = await req('DELETE', '/kv/' + k); assert.equal(r.status, 204) }
  r = await req('GET', '/kv'); assert.deepEqual(JSON.parse(r.body), all.filter((k) => !keys.slice(0, 250).includes(k)))
  r = await req('DELETE', '/kv/' + keys[0]); assert.equal(r.status, 404)
  console.log('stress OK')
} finally { child.kill() }
