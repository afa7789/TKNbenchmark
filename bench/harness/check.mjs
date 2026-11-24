#!/usr/bin/env node
// Black-box checker. Builds with build.sh, then runs cases.json against ./app.
// Usage: node check.mjs [--no-build] [--cases file.json] [--json]
// Standalone on purpose: it is copied into every agent workdir.
import { spawn, spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { isDeepStrictEqual } from 'node:util'
import { fileURLToPath } from 'node:url'
import http from 'node:http'
import net from 'node:net'

// ---------- deterministic input generators (shared with the case builders) ----------

export function rng(seed) {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const SYLLABLES = ['ka', 'zu', 'mi', 'ro', 'te', 'an', 'ul', 'bo', 'si', 'qe', 'ny', 'ox']
const SEPARATORS = [' ', ' ', ' ', '\n', ', ', '. ', '-', '42', "'", '\t', '\xff', '\xc3(', '_']

function genWords({ seed, bytes }) {
  const r = rng(seed)
  const vocab = Array.from({ length: 4000 }, (_, i) => {
    let w = ''
    for (let n = 1 + (i % 4); n > 0; n--) w += SYLLABLES[Math.floor(r() * SYLLABLES.length)]
    return w
  })
  const parts = []
  let size = 0
  while (size < bytes) {
    let w = vocab[Math.floor(r() ** 3 * vocab.length)]
    if (r() < 0.1) w = w.toUpperCase()
    const sep = SEPARATORS[Math.floor(r() * SEPARATORS.length)]
    parts.push(w, sep)
    size += w.length + sep.length
  }
  return Buffer.from(parts.join(''), 'latin1')
}

function genLru({ seed, ops, cap, keys }) {
  const r = rng(seed)
  const lines = [String(cap)]
  for (let i = 0; i < ops; i++) {
    const k = 'k' + Math.floor(r() * keys)
    const p = r()
    if (p < 0.5) lines.push(`SET ${k} v${Math.floor(r() * 1e9)}`)
    else if (p < 0.85) lines.push(`GET ${k}`)
    else if (p < 0.97) lines.push(`DEL ${k}`)
    else lines.push('SIZE')
  }
  return Buffer.from(lines.join('\n') + '\n')
}

const NUMS = ['0', '1', '7', '12', '255', '1000', '65536', '4294967296', '9223372036854775807', '3037000499']

function genExpr(r, depth) {
  const p = r()
  if (depth <= 0 || p < 0.25) return NUMS[Math.floor(r() * NUMS.length)]
  if (p < 0.35) return '-' + genExpr(r, depth - 1)
  if (p < 0.5) return '(' + genExpr(r, depth - 1) + ')'
  const op = '+-*/%'[Math.floor(r() * 5)]
  return genExpr(r, depth - 1) + ' ' + op + ' ' + genExpr(r, depth - 1)
}

function corrupt(r, s) {
  const junk = ['(', ')', '+', '*', 'x', '', '1 1', '--']
  const at = Math.floor(r() * (s.length + 1))
  return s.slice(0, at) + junk[Math.floor(r() * junk.length)] + s.slice(at)
}

function genCalc({ seed, lines }) {
  const r = rng(seed)
  const out = []
  for (let i = 0; i < lines; i++) {
    const e = genExpr(r, 1 + Math.floor(r() * 5))
    out.push(r() < 0.1 ? corrupt(r, e) : e)
  }
  return Buffer.from(out.join('\n') + '\n')
}

export function genBytes({ seed, n }) {
  const r = rng(seed)
  const b = Buffer.alloc(n)
  for (let i = 0; i < n; i++) b[i] = Math.floor(r() * 256)
  return b
}

const GENERATORS = { words: genWords, lru: genLru, calc: genCalc, bytes: genBytes }

export function genInput(gen) {
  return GENERATORS[gen.type](gen)
}

export const sha256 = (buf) => createHash('sha256').update(buf).digest('hex')

// ---------- stdio cases ----------

function caseStdin(c) {
  if (c.gen) return genInput(c.gen)
  if (c.stdinB64) return Buffer.from(c.stdinB64, 'base64')
  return Buffer.from(c.stdin ?? '')
}

function runProcess(args, stdin, timeoutMs) {
  return new Promise((resolve) => {
    const child = spawn('./app', args, { stdio: ['pipe', 'pipe', 'pipe'] })
    const out = []
    const err = []
    const timer = setTimeout(() => child.kill('SIGKILL'), timeoutMs)
    child.stdout.on('data', (d) => out.push(d))
    child.stderr.on('data', (d) => err.push(d))
    child.on('error', (e) => resolve({ code: -1, stdout: Buffer.alloc(0), stderr: String(e), timedOut: false }))
    child.on('close', (code, signal) => {
      clearTimeout(timer)
      resolve({ code, signal, stdout: Buffer.concat(out), stderr: Buffer.concat(err).toString(), timedOut: signal === 'SIGKILL' })
    })
    child.stdin.on('error', () => {})
    child.stdin.end(stdin)
  })
}

const trimEnd = (s) => s.replace(/\n+$/, '')
const clip = (s) => (s.length > 300 ? s.slice(0, 300) + '…' : s)

function compareStdout(c, stdout) {
  if (c.stdoutSha256) {
    const got = sha256(Buffer.from(trimEnd(stdout.toString('latin1')), 'latin1'))
    return got === c.stdoutSha256 ? null : 'stdout hash mismatch (large output differs)'
  }
  const got = trimEnd(stdout.toString())
  const want = trimEnd(c.stdout)
  return got === want ? null : `expected:\n${clip(want)}\n--- got:\n${clip(got)}`
}

async function runStdioCase(c) {
  const stdin = caseStdin(c)
  const t0 = performance.now()
  const res = await runProcess(c.args ?? [], stdin, c.timeoutMs ?? 10000)
  const ms = Math.round(performance.now() - t0)
  if (res.timedOut) return { ok: false, ms, why: `timeout after ${c.timeoutMs ?? 10000} ms` }
  if (res.code !== 0) return { ok: false, ms, why: `exit code ${res.code} ${res.signal ?? ''} ${clip(res.stderr)}` }
  const why = compareStdout(c, res.stdout)
  return { ok: !why, ms, why }
}

// ---------- http cases ----------

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer()
    srv.on('error', reject)
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address()
      srv.close(() => resolve(port))
    })
  })
}

function stepBody(step) {
  if (step.bodyGen) return genInput(step.bodyGen)
  if (step.body !== undefined) return Buffer.from(step.body)
  return null
}

function request(port, step) {
  const [method, path] = step.req
  const body = stepBody(step)
  const headers = { Connection: 'close' }
  if (body) headers['Content-Length'] = body.length
  return new Promise((resolve) => {
    const req = http.request({ host: '127.0.0.1', port, method, path, headers, agent: false, timeout: 5000 }, (res) => {
      const chunks = []
      res.on('data', (d) => chunks.push(d))
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }))
      res.on('error', (e) => resolve({ error: String(e) }))
    })
    req.on('timeout', () => req.destroy(new Error('request timeout')))
    req.on('error', (e) => resolve({ error: String(e) }))
    req.end(body ?? undefined)
  })
}

function jsonMismatch(want, body) {
  try {
    return isDeepStrictEqual(JSON.parse(body.toString()), want) ? null : `json ${clip(JSON.stringify(want))} got ${clip(body.toString())}`
  } catch {
    return `invalid json body: ${clip(body.toString())}`
  }
}

const RESPONSE_CHECKS = [
  (e, res) => e.body !== undefined && res.body.toString() !== e.body && `body ${clip(res.body.toString())}, want ${clip(e.body)}`,
  (e, res) => e.sha256 && sha256(res.body) !== e.sha256 && `body bytes differ (${res.body.length} bytes)`,
  (e, res) => e.type && !String(res.headers['content-type'] ?? '').includes(e.type) && `content-type ${res.headers['content-type']}, want ${e.type}`,
  (e, res) => e.json !== undefined && jsonMismatch(e.json, res.body),
]

function checkResponse(step, res) {
  const label = step.req.join(' ')
  if (res.error) return `${label}: ${res.error}`
  if (res.status !== step.expect.status) return `${label}: status ${res.status}, want ${step.expect.status}`
  for (const check of RESPONSE_CHECKS) {
    const why = check(step.expect, res)
    if (why) return `${label}: ${why}`
  }
  return null
}

async function runStep(port, step) {
  if (!step.parallel) return checkResponse(step, await request(port, step))
  const results = await Promise.all(step.parallel.map((s) => runStep(port, s)))
  return results.find(Boolean) ?? null
}

async function waitReady(port, child, ms) {
  const deadline = Date.now() + ms
  while (Date.now() < deadline) {
    if (child.exitCode !== null) return `server exited with code ${child.exitCode}`
    const res = await request(port, { req: ['GET', '/health'] })
    if (res.status === 200) return null
    await new Promise((r) => setTimeout(r, 50))
  }
  return `server not ready after ${ms} ms`
}

async function runHttpCase(c) {
  const port = await freePort()
  const child = spawn('./app', [String(port)], { stdio: ['ignore', 'ignore', 'pipe'] })
  child.on('error', () => {})
  const t0 = performance.now()
  try {
    let why = await waitReady(port, child, 3000)
    for (const step of c.steps) {
      if (why) break
      why = await runStep(port, step)
    }
    return { ok: !why, ms: Math.round(performance.now() - t0), why }
  } finally {
    child.kill('SIGKILL')
  }
}

// ---------- main ----------

function build() {
  const t0 = performance.now()
  const res = spawnSync('bash', ['build.sh'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
  const secs = ((performance.now() - t0) / 1000).toFixed(2)
  if (res.status === 0) {
    console.log(`BUILD ok (${secs}s)`)
    return true
  }
  const tail = `${res.stdout ?? ''}${res.stderr ?? ''}`.split('\n').slice(-40).join('\n')
  console.log(`BUILD FAIL (${secs}s)\n${tail}`)
  return false
}

async function main() {
  const argv = process.argv.slice(2)
  const file = argv.includes('--cases') ? argv[argv.indexOf('--cases') + 1] : 'cases.json'
  const suite = JSON.parse(readFileSync(file, 'utf8'))
  const total = suite.cases.length
  if (!argv.includes('--no-build') && !build()) {
    console.log(`RESULT pass=0 total=${total} build=fail`)
    process.exit(1)
  }
  const run = suite.kind === 'http' ? runHttpCase : runStdioCase
  const results = []
  for (const c of suite.cases) {
    const r = await run(c)
    results.push({ name: c.name, ...r })
    if (!r.ok) console.log(`FAIL ${c.name}: ${r.why}`)
  }
  const pass = results.filter((r) => r.ok).length
  console.log(`RESULT pass=${pass} total=${total}`)
  if (argv.includes('--json')) console.log(JSON.stringify({ pass, total, results }))
  process.exit(pass === total ? 0 : 1)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main()
