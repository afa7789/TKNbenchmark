// Reference for notes: node:http + node:sqlite. node reference.mjs <port>, data in $NOTES_DB.
import http from 'node:http'
import { DatabaseSync } from 'node:sqlite'

const db = new DatabaseSync(process.env.NOTES_DB)
db.exec(`CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, tags TEXT NOT NULL)`)

const TAG = /^[a-z0-9-]{1,32}$/
const ID = /^[1-9][0-9]*$/
const UINT = /^[0-9]+$/
const lowerAscii = (s) => s.replace(/[A-Z]/g, (c) => c.toLowerCase())
const row = (r) => r && { id: Number(r.id), title: r.title, body: r.body, tags: JSON.parse(r.tags) }
const all = () => db.prepare('SELECT * FROM notes ORDER BY id').all().map(row)

class Bad extends Error {}

const trim = (s) => s.replace(/^ +| +$/g, '')
const isTags = (t) => Array.isArray(t) && t.every((x) => typeof x === 'string' && TAG.test(x))

// The SPEC's rules for a note's fields, in order: [broken?, message].
const RULES = [
  [(v) => v === null || typeof v !== 'object' || Array.isArray(v), 'body must be an object'],
  [(v) => typeof v.title !== 'string', 'title must be a string'],
  [(v) => [...trim(v.title)].length < 1 || [...trim(v.title)].length > 200, 'title must have 1-200 characters'],
  [(v) => v.body !== undefined && typeof v.body !== 'string', 'body must be a string'],
  [(v) => v.tags !== undefined && !isTags(v.tags), 'invalid tags'],
]

function parse(text) {
  try {
    return JSON.parse(text)
  } catch {
    throw new Bad('invalid JSON')
  }
}

// A note's fields from a request body, or Bad.
function fields(text) {
  const v = parse(text)
  const broken = RULES.find(([fails]) => fails(v))
  if (broken) throw new Bad(broken[1])
  return { title: trim(v.title), body: v.body ?? '', tags: [...new Set(v.tags ?? [])].sort() }
}

function list(query) {
  for (const k of ['limit', 'after']) if (query.has(k) && !UINT.test(query.get(k))) throw new Bad(`invalid ${k}`)
  const limit = query.has('limit') ? Number(query.get('limit')) : 100
  if (limit < 1 || limit > 100) throw new Bad('invalid limit')
  const after = Number(query.get('after') ?? 0)
  const tag = query.get('tag')
  const q = query.has('q') ? lowerAscii(query.get('q')) : null
  const notes = all().filter((n) => n.id > after && (tag === null || n.tags.includes(tag)) && (q === null || lowerAscii(n.title).includes(q) || lowerAscii(n.body).includes(q)))
  return { notes: notes.slice(0, limit) }
}

function tagCounts() {
  const counts = {}
  for (const n of all()) for (const t of n.tags) counts[t] = (counts[t] ?? 0) + 1
  return counts
}

const ROUTES = {
  'POST /notes': (_, body) => {
    const f = fields(body)
    const r = db.prepare('INSERT INTO notes (title, body, tags) VALUES (?, ?, ?)').run(f.title, f.body, JSON.stringify(f.tags))
    return [201, { id: Number(r.lastInsertRowid), ...f }]
  },
  'GET /notes': (url) => [200, list(url.searchParams)],
  'GET /note': (_, __, id) => {
    const n = row(db.prepare('SELECT * FROM notes WHERE id = ?').get(id))
    return n ? [200, n] : [404, { error: 'not found' }]
  },
  'PUT /note': (_, body, id) => {
    const f = fields(body)
    const r = db.prepare('UPDATE notes SET title = ?, body = ?, tags = ? WHERE id = ?').run(f.title, f.body, JSON.stringify(f.tags), id)
    return r.changes ? [200, { id, ...f }] : [404, { error: 'not found' }]
  },
  'DELETE /note': (_, __, id) => (db.prepare('DELETE FROM notes WHERE id = ?').run(id).changes ? [204, null] : [404, { error: 'not found' }]),
  'GET /stats': () => [200, { notes: all().length, tags: tagCounts() }],
  'GET /tags': () => [200, { tags: Object.entries(tagCounts()).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).map(([tag, count]) => ({ tag, count })) }],
}
const PATHS = { '/notes': 'notes', '/stats': 'stats', '/tags': 'tags' }

// [route key, id] for a method and path; 404 / 405 as [status].
function route(method, path) {
  const m = path.match(/^\/notes\/([^/]+)$/)
  if (m) return !ID.test(m[1]) ? [404] : ROUTES[`${method} /note`] ? [`${method} /note`, Number(m[1])] : [405]
  if (!PATHS[path]) return [404]
  return ROUTES[`${method} ${path}`] ? [`${method} ${path}`] : [405]
}

function send(res, status, value) {
  if (value === null) return res.writeHead(status).end()
  res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(value))
}

function handle(req, res, body) {
  const url = new URL(req.url, 'http://x')
  if (url.pathname === '/health') return req.method === 'GET' ? res.writeHead(200, { 'Content-Type': 'text/plain' }).end('ok') : send(res, 405, { error: 'method not allowed' })
  const [key, id] = route(req.method, url.pathname)
  if (typeof key === 'number') return send(res, key, { error: key === 404 ? 'not found' : 'method not allowed' })
  try {
    send(res, ...ROUTES[key](url, body, id))
  } catch (e) {
    if (!(e instanceof Bad)) throw e
    send(res, 400, { error: e.message })
  }
}

http
  .createServer((req, res) => {
    const chunks = []
    req.on('data', (d) => chunks.push(d))
    req.on('end', () => handle(req, res, Buffer.concat(chunks).toString()))
  })
  .listen(Number(process.argv[2]), '127.0.0.1')
