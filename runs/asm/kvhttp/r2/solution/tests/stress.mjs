import http from 'node:http'
import { spawn } from 'node:child_process'
import crypto from 'node:crypto'
const port = 20000 + Math.floor(Math.random() * 40000)
const child = spawn('./app', [String(port)], { stdio: 'inherit' })
const req = (method, path, body) => new Promise((res) => {
  const headers = { Connection: 'close' }; if (body) headers['Content-Length'] = body.length
  const r = http.request({ host: '127.0.0.1', port, method, path, headers, agent: false }, (s) => {
    const c = []; s.on('data', (d) => c.push(d)); s.on('end', () => res({ status: s.statusCode, body: Buffer.concat(c) }))
  }); r.on('error', (e) => res({ error: String(e) })); r.end(body)
})
await new Promise((r) => setTimeout(r, 300))
const vals = new Map(); let bad = 0
for (let round = 0; round < 10; round++) {
  await Promise.all(Array.from({ length: 128 }, async (_, i) => {
    const k = 'k' + ((i * 7 + round) % 300), v = crypto.randomBytes(Math.floor(Math.random() * 200000))
    const p = await req('PUT', '/kv/' + k, v); if (p.status !== 200 && p.status !== 201) bad++
    const g = await req('GET', '/kv/' + k); if (g.status !== 200) bad++
  }))
}
const l = await req('GET', '/kv'); console.log('keys', JSON.parse(l.body).length, 'bad', bad, 'alive', child.exitCode === null)
child.kill()
