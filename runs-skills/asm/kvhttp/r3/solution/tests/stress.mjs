import http from 'node:http'
import net from 'node:net'
import { spawn } from 'node:child_process'
import { randomBytes } from 'node:crypto'
const port = 20000 + Math.floor(Math.random() * 40000)
const child = spawn('./app', [String(port)], { stdio: 'inherit' })
const req = (method, path, body) => new Promise((resolve) => {
  const headers = { Connection: 'close' }
  if (body) headers['Content-Length'] = body.length
  const r = http.request({ host: '127.0.0.1', port, method, path, headers, agent: false }, (res) => {
    const c = []; res.on('data', (d) => c.push(d)); res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(c) }))
  })
  r.on('error', (e) => resolve({ error: String(e) }))
  r.end(body)
})
const raw = (data) => new Promise((resolve) => {
  const s = net.connect(port, '127.0.0.1', () => s.end(data)); const c = []
  s.on('data', (d) => c.push(d)); s.on('end', () => resolve(Buffer.concat(c).toString())); s.on('error', (e) => resolve(String(e)))
})
let fails = 0
const eq = (name, got, want) => { if (got !== want) { fails++; console.log('FAIL', name, got, want) } }
await new Promise((r) => setTimeout(r, 200))
eq('health', (await req('GET', '/health')).body.toString(), 'ok')
eq('kv empty', (await req('GET', '/kv')).body.toString(), '[]')
const big = randomBytes(1 << 20)
eq('put big', (await req('PUT', '/kv/big', big)).status, 201)
const g = await req('GET', '/kv/big'); eq('get big', Buffer.compare(g.body, big), 0)
eq('too big', (await req('PUT', '/kv/big2', randomBytes((1 << 20) + 1))).status, 413)
eq('empty val', (await req('PUT', '/kv/e', Buffer.alloc(0))).status, 201)
const e = await req('GET', '/kv/e'); eq('get empty', e.status, 200); eq('get empty len', e.body.length, 0)
eq('k64', (await req('PUT', '/kv/' + 'a'.repeat(64), Buffer.from('x'))).status, 201)
eq('k65', (await req('PUT', '/kv/' + 'a'.repeat(65), Buffer.from('x'))).status, 400)
eq('empty key', (await req('GET', '/kv/')).status, 400)
eq('slash', (await req('GET', '/kv/a/b')).status, 400)
eq('pct', (await req('GET', '/kv/a%20')).status, 400)
eq('post kv', (await req('POST', '/kv')).status, 405)
eq('del health', (await req('DELETE', '/health')).status, 405)
eq('root', (await req('GET', '/')).status, 404)
eq('kvx', (await req('GET', '/kvx')).status, 404)
eq('healthx', (await req('GET', '/healthz')).status, 404)
eq('head kv', (await req('HEAD', '/kv/a')).status, 405)
// many keys + parallel
const keys = Array.from({ length: 3000 }, (_, i) => 'K' + i.toString(36) + '_-')
for (let i = 0; i < keys.length; i += 100)
  await Promise.all(keys.slice(i, i + 100).map((k) => req('PUT', '/kv/' + k, Buffer.from(k + '!')).then((r) => eq('put ' + k, r.status, 201))))
const par = await Promise.all(keys.slice(0, 200).map((k) => req('GET', '/kv/' + k)))
par.forEach((r, i) => eq('pget', r.body?.toString(), keys[i] + '!'))
const list = JSON.parse((await req('GET', '/kv')).body.toString())
const want = [...keys, 'big', 'e', 'a'.repeat(64)].sort()
eq('list', JSON.stringify(list), JSON.stringify(want))
await Promise.all(keys.map((k) => req('DELETE', '/kv/' + k).then((r) => eq('del', r.status, 204))))
eq('list2', (await req('GET', '/kv')).body.toString(), JSON.stringify(['a'.repeat(64), 'big', 'e']))
eq('replace', (await req('PUT', '/kv/e', Buffer.from('zz'))).status, 200)
console.log(await raw('GET /health HTTP/1.1\r\nHost: x\r\ncontent-LENGTH:  0 \r\n\r\n'))
console.log(await raw('garbage\r\n\r\n'))
console.log((await raw('PUT /kv/q HTTP/1.1\r\nContent-Length: 5\r\n\r\nab')).slice(0, 40))
console.log('fails', fails)
child.kill()
