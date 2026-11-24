import { genInput, sha256 } from '../../harness/check.mjs'

const step = (method, path, status, extra = {}) => {
  const { body, ...expect } = extra
  return { req: [method, path], ...(body !== undefined && { body }), expect: { status, ...expect } }
}

const keys = (n) => Array.from({ length: n }, (_, i) => `key-${String(i).padStart(2, '0')}`)
const big = { type: 'bytes', seed: 42, n: 1024 * 1024 }

export const visible = () => ({
  kind: 'http',
  cases: [
    { name: 'health', steps: [step('GET', '/health', 200, { body: 'ok' })] },
    {
      name: 'crud',
      steps: [
        step('PUT', '/kv/a', 201, { body: 'hello' }),
        step('GET', '/kv/a', 200, { body: 'hello' }),
        step('PUT', '/kv/a', 200, { body: 'world' }),
        step('GET', '/kv/a', 200, { body: 'world' }),
        step('DELETE', '/kv/a', 204),
        step('GET', '/kv/a', 404),
        step('DELETE', '/kv/a', 404),
      ],
    },
    {
      name: 'list-sorted',
      steps: [
        step('PUT', '/kv/b', 201, { body: '2' }),
        step('PUT', '/kv/a', 201, { body: '1' }),
        step('PUT', '/kv/c', 201, { body: '3' }),
        step('GET', '/kv', 200, { json: ['a', 'b', 'c'], type: 'application/json' }),
      ],
    },
    {
      name: 'errors',
      steps: [
        step('GET', '/nope', 404),
        step('POST', '/health', 405),
        step('GET', '/kv/bad.key', 400),
        step('PUT', '/kv/a', 201, { body: 'x' }),
        step('PATCH', '/kv/a', 405),
      ],
    },
  ],
})

export const hidden = () => ({
  kind: 'http',
  cases: [
    ...visible().cases,
    { name: 'empty-list', steps: [step('GET', '/kv', 200, { json: [], type: 'application/json' })] },
    {
      name: 'empty-value',
      steps: [step('PUT', '/kv/e', 201, { body: '' }), step('GET', '/kv/e', 200, { body: '' }), step('GET', '/kv', 200, { json: ['e'] })],
    },
    {
      name: 'binary-1mib',
      steps: [
        { req: ['PUT', '/kv/blob'], bodyGen: big, expect: { status: 201 } },
        step('GET', '/kv/blob', 200, { sha256: sha256(genInput(big)) }),
      ],
    },
    {
      name: 'key-rules',
      steps: [
        step('PUT', `/kv/${'k'.repeat(64)}`, 201, { body: 'ok' }),
        step('PUT', `/kv/${'k'.repeat(65)}`, 400, { body: 'no' }),
        step('GET', '/kv/', 400),
        step('GET', '/kv/a/b', 400),
        step('GET', '/kv/a%20b', 400),
        step('PUT', '/kv/A-z_9', 201, { body: 'ok' }),
        step('GET', '/kv', 200, { json: ['A-z_9', 'k'.repeat(64)] }),
      ],
    },
    {
      name: 'methods',
      steps: [step('POST', '/kv', 405), step('DELETE', '/kv', 405), step('POST', '/kv/a', 405), step('DELETE', '/health', 405), step('GET', '/', 404)],
    },
    {
      name: 'value-bytes-preserved',
      steps: [step('PUT', '/kv/crlf', 201, { body: 'line1\r\nline2\r\n\r\n{"j":1}' }), step('GET', '/kv/crlf', 200, { body: 'line1\r\nline2\r\n\r\n{"j":1}' })],
    },
    {
      name: 'concurrent-64',
      steps: [
        { parallel: keys(64).map((k) => step('PUT', `/kv/${k}`, 201, { body: `v-${k}` })) },
        { parallel: keys(64).map((k) => step('GET', `/kv/${k}`, 200, { body: `v-${k}` })) },
        step('GET', '/kv', 200, { json: keys(64) }),
        { parallel: keys(64).map((k) => step('DELETE', `/kv/${k}`, 204)) },
        step('GET', '/kv', 200, { json: [] }),
      ],
    },
  ],
})
