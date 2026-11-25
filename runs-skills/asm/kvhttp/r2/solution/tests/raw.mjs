import net from 'node:net'
import { spawn } from 'node:child_process'
const port = 20000 + Math.floor(Math.random() * 40000)
const child = spawn('./app', [String(port)], { stdio: 'inherit' })
await new Promise((r) => setTimeout(r, 200))
const raw = (chunks, delay = 20) => new Promise((res) => {
  const s = net.connect(port, '127.0.0.1'); const out = []
  s.on('data', (d) => out.push(d)); s.on('end', () => res(Buffer.concat(out).toString())); s.on('error', (e) => res('ERR ' + e))
  s.on('connect', async () => { for (const c of chunks) { s.write(c); await new Promise((r) => setTimeout(r, delay)) } })
})
try {
  console.log(JSON.stringify(await raw(['PUT /kv/x HT', 'TP/1.1\r\ncontent-length:  5 \r\nHost: a\r', '\n\r\n', 'he', 'llo'])))
  console.log(JSON.stringify(await raw(['GET /kv/x HTTP/1.1\r\n\r\n'])))
  // 100 slow clients held open simultaneously while fast ones complete
  const slow = Array.from({ length: 100 }, (_, i) => raw(['PUT /kv/s' + i + ' HTTP/1.1\r\nContent-Length: 2\r\n\r\n', 'a', 'b'], 300))
  const fast = await raw(['GET /health HTTP/1.1\r\n\r\n'])
  console.log('fast while slow pending:', JSON.stringify(fast))
  const r = await Promise.all(slow); console.log('slow 201s:', r.filter((x) => x.startsWith('HTTP/1.1 201')).length)
  console.log(JSON.stringify(await raw(['garbage\r\n\r\n'])))
  console.log(JSON.stringify(await raw(['GET /kv HTTP/1.1\r\nContent-Length: abc\r\n\r\n'])))
} finally { child.kill() }
