import net from 'node:net'
import { spawn } from 'node:child_process'
const port = 20000 + Math.floor(Math.random() * 40000)
const child = spawn('./app', [String(port)], { stdio: 'inherit' })
await new Promise((r) => setTimeout(r, 200))
const parts = ['PUT /kv/sp HTTP/1.1\r', '\nContent-Length: 6\r\n', '\r', '\nabc', 'def']
const out = await new Promise((resolve) => {
  const s = net.connect(port, '127.0.0.1', async () => {
    for (const p of parts) { s.write(p); await new Promise((r) => setTimeout(r, 50)) }
  })
  const c = []; s.on('data', (d) => c.push(d)); s.on('end', () => resolve(Buffer.concat(c).toString()))
})
console.log(out.split('\r\n')[0])
const idle = await Promise.all(Array.from({ length: 100 }, () => new Promise((r) => { const s = net.connect(port, '127.0.0.1', () => r(s)) })))
const g = await new Promise((resolve) => {
  const s = net.connect(port, '127.0.0.1', () => s.end('GET /kv/sp HTTP/1.1\r\n\r\n'))
  const c = []; s.on('data', (d) => c.push(d)); s.on('end', () => resolve(Buffer.concat(c).toString()))
})
console.log(JSON.stringify(g))
idle.forEach((s) => s.destroy()); child.kill()
