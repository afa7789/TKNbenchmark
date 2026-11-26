#!/usr/bin/env node
// Black-box checker. Builds with build.sh, then runs cases.json against ./app.
// Usage: node check.mjs [--no-build] [--cases file.json] [--json]
// Standalone on purpose: it is copied into every agent workdir.
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { isDeepStrictEqual } from 'node:util'
import { fileURLToPath } from 'node:url'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
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

const fix = (x, d) => Number(x.toFixed(d))

// Regression data: y = b0 + sum(bj * xj) + noise, printed with 4 decimals.
function genLinreg({ seed, n, k, noise = 0.5 }) {
  const r = rng(seed)
  const beta = Array.from({ length: k + 1 }, () => fix(r() * 10 - 5, 2))
  const lines = [`${n} ${k}`]
  for (let i = 0; i < n; i++) {
    const x = Array.from({ length: k }, () => fix(r() * 20 - 10, 4))
    const y = beta[0] + x.reduce((s, v, j) => s + beta[j + 1] * v, 0) + (r() * 2 - 1) * noise
    lines.push([...x, fix(y, 4)].join(' '))
  }
  return Buffer.from(lines.join('\n') + '\n')
}

// Symmetric positive-definite A = M'M + n*I and a vector b, printed with 6 decimals.
function genSpd({ seed, n }) {
  const r = rng(seed)
  const m = Array.from({ length: n }, () => Array.from({ length: n }, () => fix(r() * 2 - 1, 3)))
  const a = m.map((_, i) => m.map((__, j) => m.reduce((s, row) => s + row[i] * row[j], 0) + (i === j ? n : 0)))
  const b = Array.from({ length: n }, () => fix(r() * 20 - 10, 3))
  return Buffer.from([String(n), ...a.map((row) => row.map((v) => v.toFixed(6)).join(' ')), b.join(' ')].join('\n') + '\n')
}

const GENERATORS = { words: genWords, lru: genLru, calc: genCalc, bytes: genBytes, linreg: genLinreg, spd: genSpd }

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

// Numeric outputs: same number of tokens, each within tolerance (relative, or absolute below 1).
function compareNumbers(c, stdout) {
  const got = stdout.toString().trim().split(/\s+/).filter(Boolean)
  const want = c.stdout.trim().split(/\s+/).filter(Boolean)
  if (got.length !== want.length) return `expected ${want.length} numbers, got ${got.length}:\n${clip(stdout.toString())}`
  const bad = want.findIndex((w, i) => !(Math.abs(Number(got[i]) - Number(w)) <= c.tolerance * Math.max(1, Math.abs(Number(w)))))
  return bad < 0 ? null : `number ${bad + 1}: expected ${want[bad]}, got ${got[bad]} (tolerance ${c.tolerance})`
}

function compareStdout(c, stdout) {
  if (c.tolerance) return compareNumbers(c, stdout)
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

// A case's environment: c.env values with {tmp} set to a fresh directory outside the solution (for a
// database file, say). Cases without env run with the checker's own environment, as before.
function caseEnv(c) {
  if (!c.env) return { env: process.env, tmp: null }
  const tmp = mkdtempSync(join(tmpdir(), 'case-'))
  const vars = Object.fromEntries(Object.entries(c.env).map(([k, v]) => [k, v.replaceAll('{tmp}', tmp)]))
  return { env: { ...process.env, ...vars }, tmp }
}

function startServer(ctx) {
  ctx.child = spawn('./app', [String(ctx.port)], { stdio: ['ignore', 'ignore', 'pipe'], env: ctx.env })
  ctx.child.on('error', () => {})
  return waitReady(ctx.port, ctx.child, 3000)
}

// Steps beyond a request: restart the server (same port and environment), or check that the file named by
// an environment variable starts with given bytes (a SQLite database, say).
async function runCaseStep(ctx, step) {
  if (step.restart) {
    const exited = new Promise((r) => (ctx.child.exitCode === null ? ctx.child.once('exit', r) : r()))
    ctx.child.kill('SIGKILL')
    await exited
    return startServer(ctx)
  }
  if (step.file) {
    const path = ctx.env[step.file]
    const head = existsSync(path) ? readFileSync(path).subarray(0, step.startsWith.length).toString('latin1') : ''
    return head === step.startsWith ? null : `the ${step.file} file does not start with ${JSON.stringify(step.startsWith)}`
  }
  return runStep(ctx.port, step)
}

async function runHttpCase(c) {
  const ctx = { port: await freePort(), ...caseEnv(c) }
  const t0 = performance.now()
  try {
    let why = await startServer(ctx)
    for (const step of c.steps) {
      if (why) break
      why = await runCaseStep(ctx, step)
    }
    return { ok: !why, ms: Math.round(performance.now() - t0), why }
  } finally {
    ctx.child.kill('SIGKILL')
    if (ctx.tmp) rmSync(ctx.tmp, { recursive: true, force: true })
  }
}

// ---------- proof cases ----------

// Source files with the given extension, comments removed (build and dot directories skipped).
function sources(ext, comments, dir = '.') {
  let text = ''
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const path = `${dir}/${e.name}`
    if (e.isDirectory() && !/^(\.|_build|build|node_modules)/.test(e.name)) text += sources(ext, comments, path)
    else if (e.isFile() && e.name.endsWith(ext)) text += '\n' + readFileSync(path, 'utf8')
  }
  for (const c of comments) text = text.replace(new RegExp(c, 'g'), ' ')
  return text
}

const squash = (s) => s.replace(/\s+/g, ' ').trim()

function runProofCase(c) {
  if (c.run) {
    const r = spawnSync(c.run[0], c.run.slice(1), { encoding: 'utf8', timeout: c.timeoutMs ?? 300000 })
    return r.status === 0 ? { ok: true } : { ok: false, why: clip(`${r.stdout ?? ''}${r.stderr ?? ''}`.trim() || `exit ${r.status}`) }
  }
  const text = sources(c.scan.ext, c.scan.comments)
  if (c.forbid) {
    const m = text.match(new RegExp(c.forbid))
    return m ? { ok: false, why: `forbidden: ${m[0]}` } : { ok: true }
  }
  return squash(text).includes(c.contains) ? { ok: true } : { ok: false, why: `changed or missing: ${clip(c.contains)}` }
}

// ---------- evm cases ----------

// anvil's well-known development accounts (public test keys, never real funds).
const ACCOUNTS = [
  ['0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266', '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'],
  ['0x70997970C51812dc3A010C7d01b50e0d17dc79C8', '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d'],
  ['0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC', '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a'],
]
const ZERO = '0x0000000000000000000000000000000000000000'

function cast(args) {
  const r = spawnSync('cast', args, { encoding: 'utf8', timeout: 30000 })
  return { ok: r.status === 0, out: (r.stdout ?? '').trim(), err: (r.stderr ?? '').trim() }
}

const resolve = (ctx, a) => String(a).replace(/@contract/g, ctx.address).replace(/@zero/g, ZERO).replace(/@(\d)/g, (_, i) => ACCOUNTS[i][0])
const clean = (s) => s.replace(/\s*\[[^\]]*\]$/, '').replace(/^"|"$/g, '').toLowerCase()

function rpc(ctx, method, ...params) {
  return cast(['rpc', '--rpc-url', ctx.url, method, ...params.map(String)])
}

function sendTx(ctx, step, target, extra) {
  if (step.at) rpc(ctx, 'evm_setNextBlockTimestamp', step.at)
  const value = step.value ? ['--value', String(step.value)] : []
  const r = cast(['send', '--rpc-url', ctx.url, '--private-key', ACCOUNTS[step.from ?? 0][1], '--json', ...value, ...target, ...extra])
  if (!r.ok) return { reverted: true, err: r.err }
  const receipt = JSON.parse(r.out)
  return { reverted: receipt.status !== '0x1', receipt }
}

// Does the receipt carry this event with exactly these topics and data?
function eventMismatch(ctx, ev, receipt) {
  const enc = cast(['abi-encode-event', ev.sig, ...ev.args.map((a) => resolve(ctx, a))]).out
  const want = [...enc.matchAll(/\[(topic\d|data)\]: (0x[0-9a-f]*)/g)]
  const topics = want.filter(([, k]) => k.startsWith('topic')).map(([, , v]) => v)
  const data = want.find(([, k]) => k === 'data')?.[2] ?? '0x'
  const hit = receipt.logs.some((l) => l.topics.join() === topics.join() && (l.data === data || (data === '0x' && l.data === '0x')))
  return hit ? null : `event ${ev.sig}(${ev.args.join(', ')}) not emitted as expected`
}

function stepSend(ctx, step) {
  const target = step.send ? [ctx.address, step.send, ...(step.args ?? []).map((a) => resolve(ctx, a))] : [resolve(ctx, step.to)]
  const r = sendTx(ctx, step, target, [])
  if (step.revert) return r.reverted ? null : `${step.send ?? 'transfer'} should revert`
  if (r.reverted) return `${step.send ?? 'transfer'} reverted: ${clip(r.err ?? 'status 0')}`
  return step.event ? eventMismatch(ctx, step.event, r.receipt) : null
}

function stepCall(ctx, step) {
  const r = cast(['call', '--rpc-url', ctx.url, ctx.address, step.call, ...(step.args ?? []).map((a) => resolve(ctx, a))])
  if (!r.ok) return `${step.call} failed: ${clip(r.err)}`
  return clean(r.out) === clean(resolve(ctx, step.expect)) ? null : `${step.call}(${(step.args ?? []).join(', ')}) = ${r.out}, want ${step.expect}`
}

function stepBalance(ctx, step) {
  const r = cast(['balance', '--rpc-url', ctx.url, resolve(ctx, step.balance)])
  return r.out === String(step.expect) ? null : `balance of ${step.balance} = ${r.out}, want ${step.expect}`
}

function evmStep(ctx, step) {
  if (step.call) return stepCall(ctx, step)
  if (step.balance) return stepBalance(ctx, step)
  if (step.mineAt) return rpc(ctx, 'evm_setNextBlockTimestamp', step.mineAt).ok && rpc(ctx, 'evm_mine').ok ? null : 'could not set time'
  return stepSend(ctx, step)
}

function deployContract(ctx, d) {
  const art = JSON.parse(readFileSync(`out/${d.contract}.json`, 'utf8'))
  const args = d.ctor ? cast(['abi-encode', d.ctor, ...d.args.map((a) => resolve(ctx, a))]).out.slice(2) : ''
  const r = sendTx(ctx, d, ['--create', `${art.bytecode}${args}`], [])
  if (d.revert) return r.reverted ? null : 'deployment should revert'
  if (r.reverted) return `deployment reverted: ${clip(r.err ?? 'status 0')}`
  ctx.address = r.receipt.contractAddress
  return d.event ? eventMismatch(ctx, d.event, r.receipt) : null
}

async function startAnvil(c) {
  const port = await freePort()
  const child = spawn('anvil', ['-p', String(port), '-q', '--timestamp', String(c.genesis ?? 1700000000), '--gas-price', '0', '--block-base-fee-per-gas', '0'], { stdio: 'ignore' })
  const ctx = { url: `http://127.0.0.1:${port}`, child }
  for (let i = 0; i < 100 && !cast(['block-number', '--rpc-url', ctx.url]).ok; i++) await new Promise((r) => setTimeout(r, 50))
  return ctx
}

async function runEvmCase(c) {
  const t0 = performance.now()
  const ctx = await startAnvil(c)
  try {
    let why = deployContract(ctx, c.deploy)
    for (const step of c.steps ?? []) {
      if (why) break
      why = evmStep(ctx, step)
    }
    return { ok: !why, ms: Math.round(performance.now() - t0), why }
  } catch (e) {
    return { ok: false, ms: Math.round(performance.now() - t0), why: clip(String(e.message)) }
  } finally {
    ctx.child.kill('SIGKILL')
  }
}

// ---------- zk cases ----------

// prove.sh must accept satisfiable inputs (exit 0) and reject the rest (non-zero).
function runZkCase(c) {
  writeFileSync('case-input.json', JSON.stringify(c.input))
  const t0 = performance.now()
  const r = spawnSync('bash', ['prove.sh', 'case-input.json'], { encoding: 'utf8', timeout: c.timeoutMs ?? 120000 })
  const ms = Math.round(performance.now() - t0)
  const accepted = r.status === 0
  if (accepted === (c.expect === 'accept')) return { ok: true, ms }
  const detail = accepted ? 'accepted an input that must be rejected' : `rejected a valid input: ${clip(`${r.stdout ?? ''}${r.stderr ?? ''}`.trim())}`
  return { ok: false, ms, why: detail }
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
  const run = { http: runHttpCase, proof: runProofCase, evm: runEvmCase, zk: runZkCase }[suite.kind] ?? runStdioCase
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
