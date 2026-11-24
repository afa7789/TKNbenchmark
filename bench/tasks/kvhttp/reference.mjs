import http from 'node:http'
import { fileURLToPath } from 'node:url'

const KEY = /^[A-Za-z0-9_-]{1,64}$/

function kvRoute(store, method, key, body) {
  if (!KEY.test(key)) return [400]
  const has = store.has(key)
  if (method === 'PUT') {
    store.set(key, body)
    return [has ? 200 : 201]
  }
  if (method === 'GET') return has ? [200, store.get(key)] : [404]
  if (method === 'DELETE') return [store.delete(key) ? 204 : 404]
  return [405]
}

function route(store, method, url, body) {
  if (url === '/health') return method === 'GET' ? [200, 'ok'] : [405]
  if (url === '/kv') return method === 'GET' ? [200, JSON.stringify([...store.keys()].sort()), 'application/json'] : [405]
  if (url.startsWith('/kv/')) return kvRoute(store, method, url.slice(4), body)
  return [404]
}

export function createServer() {
  const store = new Map()
  return http.createServer((req, res) => {
    const chunks = []
    req.on('data', (d) => chunks.push(d))
    req.on('end', () => {
      const [status, body = '', type = 'application/octet-stream'] = route(store, req.method, req.url, Buffer.concat(chunks))
      res.writeHead(status, { 'Content-Type': type, 'Content-Length': Buffer.byteLength(body) })
      res.end(body)
    })
  })
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  createServer().listen(Number(process.argv[2]), '127.0.0.1')
}
