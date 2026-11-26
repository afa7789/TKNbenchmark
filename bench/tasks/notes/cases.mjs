// notes: an HTTP + SQLite service. Every case gets its own database ($NOTES_DB in a fresh directory).
// visible(lang, slice) gives the examples of one slice of the work (core, crud, list, stats) for a swarm
// worker; without a slice, all of them. hidden() is a superset: persistence across restarts, the SQLite
// file itself, concurrent writes, every validation rule.
const ENV = { NOTES_DB: '{tmp}/notes.db' }
const json = (v) => JSON.stringify(v)

// One request: send is a JSON value (or a raw string), json the expected response body.
function call(method, path, status, { send, json: want, body } = {}) {
  const req = { req: [method, path] }
  if (send !== undefined) req.body = typeof send === 'string' ? send : json(send)
  return { ...req, expect: { status, ...(want !== undefined && { json: want }), ...(body !== undefined && { body }) } }
}
const note = (id, title, body = '', tags = []) => ({ id, title, body, tags })
const post = (id, title, body, tags) => call('POST', '/notes', 201, { send: { title, ...(body !== undefined && { body }), ...(tags && { tags }) }, json: note(id, title.replace(/^ +| +$/g, ''), body, [...new Set(tags ?? [])].sort()) })
const kase = (name, steps) => ({ name, env: ENV, steps })

const CORE = [
  kase('health', [call('GET', '/health', 200, { body: 'ok' })]),
  kase('create-and-get', [
    post(1, 'first'),
    post(2, '  second  ', 'some text', ['work', 'b-2', 'work']),
    call('GET', '/notes/2', 200, { json: note(2, 'second', 'some text', ['b-2', 'work']) }),
    call('GET', '/notes/1', 200, { json: note(1, 'first') }),
  ]),
  kase('create-errors', [
    call('POST', '/notes', 400, { send: '{"title": ' }),
    call('POST', '/notes', 400, { send: [] }),
    call('POST', '/notes', 400, { send: {} }),
    call('POST', '/notes', 400, { send: { title: '   ' } }),
    call('POST', '/notes', 400, { send: { title: 'x', tags: ['Bad'] } }),
    call('POST', '/notes', 400, { send: { title: 'x', body: 3 } }),
  ]),
  kase('not-found', [call('GET', '/nope', 404), call('GET', '/notes/abc', 404), call('GET', '/notes/0', 404), call('GET', '/notes/7', 404)]),
]

const CRUD = [
  kase('update', [
    post(1, 'old', 'text', ['x']),
    call('PUT', '/notes/1', 200, { send: { title: 'new', tags: ['b', 'a'] }, json: note(1, 'new', '', ['a', 'b']) }),
    call('GET', '/notes/1', 200, { json: note(1, 'new', '', ['a', 'b']) }),
    call('PUT', '/notes/9', 404, { send: { title: 'none' } }),
    call('PUT', '/notes/1', 400, { send: { title: '' } }),
  ]),
  kase('delete', [
    post(1, 'a'),
    post(2, 'b'),
    call('DELETE', '/notes/1', 204, { body: '' }),
    call('GET', '/notes/1', 404),
    call('DELETE', '/notes/1', 404),
    post(3, 'c'),
  ]),
]

const LIST = [
  kase('list-all', [post(1, 'a'), post(2, 'b', 'x', ['t']), call('GET', '/notes', 200, { json: { notes: [note(1, 'a'), note(2, 'b', 'x', ['t'])] } })]),
  kase('filter', [
    post(1, 'Hello world', '', ['greet']),
    post(2, 'other', 'say HELLO', ['greet', 'misc']),
    post(3, 'nothing'),
    call('GET', '/notes?tag=misc', 200, { json: { notes: [note(2, 'other', 'say HELLO', ['greet', 'misc'])] } }),
    call('GET', '/notes?q=hello', 200, { json: { notes: [note(1, 'Hello world', '', ['greet']), note(2, 'other', 'say HELLO', ['greet', 'misc'])] } }),
    call('GET', '/notes?q=hello&tag=misc', 200, { json: { notes: [note(2, 'other', 'say HELLO', ['greet', 'misc'])] } }),
  ]),
  kase('paging', [
    ...[1, 2, 3, 4, 5].map((i) => post(i, `n${i}`)),
    call('GET', '/notes?limit=2', 200, { json: { notes: [note(1, 'n1'), note(2, 'n2')] } }),
    call('GET', '/notes?after=2&limit=2', 200, { json: { notes: [note(3, 'n3'), note(4, 'n4')] } }),
    call('GET', '/notes?limit=0', 400),
  ]),
]

const STATS = [
  kase('stats', [
    post(1, 'a', '', ['x', 'y']),
    post(2, 'b', '', ['x']),
    post(3, 'c'),
    call('GET', '/stats', 200, { json: { notes: 3, tags: { x: 2, y: 1 } } }),
    call('GET', '/tags', 200, { json: { tags: [{ tag: 'x', count: 2 }, { tag: 'y', count: 1 }] } }),
  ]),
  kase('stats-empty', [call('GET', '/stats', 200, { json: { notes: 0, tags: {} } }), call('GET', '/tags', 200, { json: { tags: [] } })]),
]

const SLICES = { core: CORE, crud: CRUD, list: LIST, stats: STATS }

const HIDDEN = [
  kase('persistence', [
    post(1, 'kept', 'body', ['p']),
    post(2, 'gone'),
    { restart: true },
    call('GET', '/notes', 200, { json: { notes: [note(1, 'kept', 'body', ['p']), note(2, 'gone')] } }),
    call('DELETE', '/notes/2', 204, { body: '' }),
    { restart: true },
    post(3, 'after restart'),
    call('GET', '/stats', 200, { json: { notes: 2, tags: { p: 1 } } }),
  ]),
  kase('sqlite-file', [post(1, 'on disk'), { file: 'NOTES_DB', startsWith: 'SQLite format 3\0' }]),
  kase('concurrent-writes', [
    { parallel: Array.from({ length: 32 }, (_, i) => call('POST', '/notes', 201, { send: { title: `t${i}` } })) },
    call('GET', '/stats', 200, { json: { notes: 32, tags: {} } }),
    post(33, 'next'),
  ]),
  kase('title-limits', [
    post(1, 'x'.repeat(200)),
    call('POST', '/notes', 400, { send: { title: 'x'.repeat(201) } }),
    post(2, '  café ☕  '),
    call('POST', '/notes', 400, { send: { title: 5 } }),
    call('POST', '/notes', 400, { send: 'null' }),
  ]),
  kase('tag-rules', [
    post(1, 'a', '', ['z', 'a-1', 'z', '9']),
    call('POST', '/notes', 400, { send: { title: 'b', tags: [''] } }),
    call('POST', '/notes', 400, { send: { title: 'b', tags: ['x'.repeat(33)] } }),
    call('POST', '/notes', 400, { send: { title: 'b', tags: ['has space'] } }),
    call('POST', '/notes', 400, { send: { title: 'b', tags: 'x' } }),
    call('POST', '/notes', 400, { send: { title: 'b', tags: [1] } }),
    post(2, 'c', '', ['x'.repeat(32)]),
  ]),
  kase('put-replaces', [
    post(1, 'a', 'long body', ['t']),
    call('PUT', '/notes/1', 200, { send: { title: 'a' }, json: note(1, 'a') }),
    call('GET', '/stats', 200, { json: { notes: 1, tags: {} } }),
    call('PUT', '/notes/1', 400, { send: '[1]' }),
    call('PUT', '/notes/x', 404, { send: { title: 'a' } }),
  ]),
  kase('stats-after-delete', [
    post(1, 'a', '', ['b', 'a']),
    post(2, 'b', '', ['b']),
    post(3, 'c', '', ['c']),
    call('DELETE', '/notes/3', 204, { body: '' }),
    call('GET', '/tags', 200, { json: { tags: [{ tag: 'b', count: 2 }, { tag: 'a', count: 1 }] } }),
  ]),
  kase('list-edges', [
    ...[1, 2, 3].map((i) => post(i, `n${i}`, i === 2 ? 'Mixed CASE body' : '', i === 3 ? ['k'] : [])),
    call('GET', '/notes?q=case', 200, { json: { notes: [note(2, 'n2', 'Mixed CASE body')] } }),
    call('GET', '/notes?tag=none', 200, { json: { notes: [] } }),
    call('GET', '/notes?after=3', 200, { json: { notes: [] } }),
    call('GET', '/notes?after=0&limit=100', 200, { json: { notes: [note(1, 'n1'), note(2, 'n2', 'Mixed CASE body'), note(3, 'n3', '', ['k'])] } }),
    call('GET', '/notes?limit=101', 400),
    call('GET', '/notes?after=abc', 400),
    call('GET', '/notes?limit=1.5', 400),
  ]),
  kase('methods', [call('DELETE', '/notes', 405), call('PATCH', '/notes/1', 405), call('POST', '/stats', 405), call('PUT', '/tags', 405), call('POST', '/health', 405)]),
]

export const visible = (_lang, slice) => ({ kind: 'http', cases: slice ? SLICES[slice] : Object.values(SLICES).flat() })
export const hidden = () => ({ kind: 'http', cases: [...Object.values(SLICES).flat(), ...HIDDEN] })
