// Perf phase, one binary at a time on a quiet machine, only for runs that passed every hidden test.
// stdio tasks: median wall time of 5 runs on one large input + peak RSS.
// kvhttp: requests/second under 64 concurrent clients (median of 3 rounds) + RSS after load.
// node bench/perf.mjs [--force]
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, openSync, closeSync, readdirSync, writeFileSync } from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import { dirname, join } from 'node:path'
import { RUNS, WORK } from './config.mjs'
import { builtDir } from './verify.mjs'
import { genInput } from './harness/check.mjs'
import { parseArgs, readJson, writeJson } from './lib.mjs'

const args = parseArgs(process.argv.slice(2), {})
const INPUTS = {
  wordfreq: { type: 'words', seed: 99, bytes: 50_000_000 },
  lru: { type: 'lru', seed: 21, ops: 1_000_000, cap: 50_000, keys: 200_000 },
  calc: { type: 'calc', seed: 31, lines: 200_000 },
}
const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)]
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

function inputFile(task) {
  const file = join(WORK, 'perf-inputs', `${task}.in`)
  if (!existsSync(file)) {
    mkdirSync(join(WORK, 'perf-inputs'), { recursive: true })
    writeFileSync(file, genInput(INPUTS[task]))
  }
  return file
}

function timedRun(bin, file) {
  const fd = openSync(file, 'r')
  const t0 = performance.now()
  const r = spawnSync('/usr/bin/time', ['-l', bin], { cwd: dirname(bin), stdio: [fd, 'ignore', 'pipe'], encoding: 'utf8', timeout: 60_000 })
  const ms = performance.now() - t0
  closeSync(fd)
  const rss = Number(r.stderr.match(/(\d+)\s+maximum resident set size/)?.[1] ?? 0)
  return { ok: r.status === 0, ms, rss }
}

function perfStdio(bin, task) {
  const file = inputFile(task)
  timedRun(bin, file)
  const samples = Array.from({ length: 5 }, () => timedRun(bin, file))
  if (!samples.every((s) => s.ok)) return { ok: false }
  return { ok: true, wallMs: Math.round(median(samples.map((s) => s.ms))), minMs: Math.round(Math.min(...samples.map((s) => s.ms))), rssBytes: median(samples.map((s) => s.rss)) }
}

function freePort() {
  return new Promise((resolve) => {
    const srv = net.createServer().listen(0, '127.0.0.1', () => {
      const { port } = srv.address()
      srv.close(() => resolve(port))
    })
  })
}

function hit(port, method, path, body) {
  return new Promise((resolve) => {
    const headers = { Connection: 'close', ...(body && { 'Content-Length': body.length }) }
    const req = http.request({ host: '127.0.0.1', port, method, path, headers, agent: false, timeout: 5000 }, (res) => {
      res.resume()
      res.on('end', () => resolve(res.statusCode < 500))
    })
    req.on('error', () => resolve(false))
    req.on('timeout', () => req.destroy())
    req.end(body)
  })
}

async function load(port, total, concurrency) {
  let sent = 0
  let ok = 0
  const worker = async () => {
    while (sent < total) {
      const i = sent++
      const key = `/kv/k${i % 200}`
      const good = i % 4 === 0 ? await hit(port, 'PUT', key, Buffer.from(`value-${i}`)) : await hit(port, 'GET', key)
      if (good) ok++
    }
  }
  const t0 = performance.now()
  await Promise.all(Array.from({ length: concurrency }, worker))
  return { rps: ok / ((performance.now() - t0) / 1000), errors: total - ok }
}

async function round(bin) {
  const port = await freePort()
  const child = spawn(bin, [String(port)], { cwd: dirname(bin), stdio: 'ignore' })
  try {
    for (let i = 0; i < 60 && !(await hit(port, 'GET', '/health')); i++) await sleep(50)
    await load(port, 300, 16)
    const r = await load(port, 2000, 64)
    const rss = Number(spawnSync('ps', ['-o', 'rss=', '-p', String(child.pid)], { encoding: 'utf8' }).stdout.trim()) * 1024
    return { ...r, rss }
  } finally {
    child.kill('SIGKILL')
    await sleep(2000)
  }
}

async function perfHttp(bin) {
  const rounds = []
  for (let i = 0; i < 3; i++) rounds.push(await round(bin))
  return { ok: rounds.every((r) => r.errors === 0), rps: Math.round(median(rounds.map((r) => r.rps))), rssBytes: median(rounds.map((r) => r.rss)), errors: rounds.reduce((a, r) => a + r.errors, 0) }
}

const runs = []
for (const lang of readdirSync(RUNS, { withFileTypes: true }).filter((e) => e.isDirectory())) {
  for (const task of readdirSync(join(RUNS, lang.name))) {
    for (const rep of readdirSync(join(RUNS, lang.name, task))) runs.push(join(RUNS, lang.name, task, rep))
  }
}
for (const run of runs) {
  if (!existsSync(join(run, 'verify.json')) || (existsSync(join(run, 'perf.json')) && !args.force)) continue
  const meta = readJson(join(run, 'agent.json'))
  const bin = join(builtDir(meta.id), 'app')
  const fixed = existsSync(join(run, 'repair.json')) && readJson(join(run, 'repair.json')).fixed
  if (!(readJson(join(run, 'verify.json')).solved || fixed) || !existsSync(bin)) continue
  const perf = meta.task === 'kvhttp' ? await perfHttp(bin) : perfStdio(bin, meta.task)
  writeJson(join(run, 'perf.json'), perf)
  console.log(`${meta.id}: ${JSON.stringify(perf)}`)
}
