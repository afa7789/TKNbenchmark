import http from 'node:http'
import { spawn } from 'node:child_process'
import crypto from 'node:crypto'
const port = 20000 + Math.floor(Math.random() * 40000)
const child = spawn('./app', [String(port)], { stdio: 'inherit' })
const req = (method, path, body) => new Promise((res) => {
  const headers = { Connection: 'close' }
  if (body) headers['Content-Length'] = body.length
  const r = http.request({ host: '127.0.0.1', port, method, path, headers, agent: false }, (s) => {
    const c = []; s.on('data', (d) => c.push(d)); s.on('end', () => res({ status: s.statusCode, headers: s.headers, body: Buffer.concat(c) }))
  })
  r.on('error', (e) => res({ error: String(e) })); r.end(body)
})
await new Promise((r) => setTimeout(r, 300))
let fails = 0
const ok = (cond, msg) => { if (!cond) { fails++; console.log('FAIL', msg) } }
const t = async (m, p, b, st, body) => { const r = await req(m, p, b); ok(r.status === st, `${m} ${p} -> ${r.status} want ${st} ${r.error ?? ''}`); if (body !== undefined) ok(r.body.toString() === body, `${m} ${p} body ${r.body}`); return r }
await t('GET', '/health', null, 200, 'ok')
await t('GET', '/health/', null, 404)
await t('HEAD', '/health', null, 405)
await t('DELETE', '/kv', null, 405)
await t('GET', '/kv/', null, 400)
await t('PUT', '/kv/' + 'a'.repeat(65), Buffer.from('x'), 400)
await t('PUT', '/kv/' + 'a'.repeat(64), Buffer.from('x'), 201)
await t('GET', '/kv/a/b', null, 400)
await t('GET', '/kv/%41', null, 400)
await t('GET', '/kvx', null, 404)
await t('GET', '/', null, 404)
await t('PUT', '/kv/empty', null, 201)
await t('GET', '/kv/empty', null, 200, '')
await t('PUT', '/kv/Z-_9', Buffer.from('v'), 201)
const big = crypto.randomBytes(1 << 20)
await t('PUT', '/kv/big', big, 201)
const r = await req('GET', '/kv/big')
ok(r.status === 200 && Buffer.compare(r.body, big) === 0, 'big roundtrip ' + r.body.length)
const l = await req('GET', '/kv')
console.log(l.headers['content-type'], l.body.toString().slice(0, 200))
// concurrency
const N = 200
const res = await Promise.all(Array.from({ length: N }, (_, i) => req('PUT', '/kv/c' + i, crypto.randomBytes(i * 500))))
ok(res.every((x) => x.status === 201), 'parallel puts ' + JSON.stringify(res.filter(x=>x.status!==201).slice(0,3)))
const g = await Promise.all(Array.from({ length: N }, (_, i) => req('GET', '/kv/c' + i)))
ok(g.every((x, i) => x.status === 200 && x.body.length === i * 500), 'parallel gets')
const l2 = await req('GET', '/kv')
const keys = JSON.parse(l2.body)
ok(JSON.stringify(keys) === JSON.stringify([...keys].sort()) && keys.length === N + 5, 'list sorted ' + keys.length)
await Promise.all(Array.from({ length: N }, (_, i) => t('DELETE', '/kv/c' + i, null, 204)))
const l3 = await req('GET', '/kv'); console.log(l3.body.toString().slice(0,300))
child.kill(); console.log(fails ? `${fails} failures` : 'ALL OK')
