// Filesystem and process helpers shared by run / verify / count.
import { readdirSync, readFileSync, realpathSync, writeFileSync, mkdirSync, copyFileSync, existsSync, statSync } from 'node:fs'
import { join, dirname, basename, extname } from 'node:path'
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'

const SKIP_DIRS = new Set(['target', 'zig-out', '.zig-cache', 'zig-cache', 'nimcache', 'build', 'node_modules', '.git', 'obj', 'out', '.cache', '.sandbox-home', '_build', 'dist-newstyle', '_opam'])
// ./app is kept only when it is text: a launcher script the agent may have written by hand
// (binaries are dropped by isBinary). It never counts as code.
const HARNESS = new Set(['check.mjs', 'cases.json', 'SPEC.md', '.DS_Store'])
const LOCKFILES = new Set(['Cargo.lock', 'go.sum', 'nimble.lock', 'package-lock.json', 'build.zig.zon.lock'])
const COUNTED_EXT = new Set(['.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.rs', '.go', '.nim', '.nims', '.nimble', '.zig', '.zon', '.toml', '.mod', '.sh', '.txt', '.cfg', '.jsx', '.js', '.vue', '.svelte', '.java', '.kt', '.kts', '.gradle', '.xml', '.swift', '.s', '.S', '.asm', '.cs', '.csproj', '.sln', '.odin', '.ml', '.mli', '.opam', '.hs', '.cabal', '.yaml', '.ts', '.mts', '.cts', '.mjs', '.cjs', '.py', '.m', '.jl', '.r', '.R', '.lean', '.v', '.dfy', '.sol', '.vy', '.vyi', '.circom', '.nr', '.clj', '.cljc', '.edn'])
const COUNTED_NAMES = new Set(['Makefile', 'dune', 'dune-project', 'package.json', 'tsconfig.json'])
const MAX_SOURCE_BYTES = 200 * 1024

export const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'))
export const shortSha = (text) => createHash('sha256').update(text).digest('hex').slice(0, 12)

export function writeJson(p, data) {
  mkdirSync(dirname(p), { recursive: true })
  writeFileSync(p, JSON.stringify(data, null, 2) + '\n')
}

const isBinary = (p) => readFileSync(p).subarray(0, 8192).includes(0)

function keepFile(full, name) {
  if (HARNESS.has(name) || name.endsWith('.o') || name.endsWith('.a')) return false
  return statSync(full).size <= 2 * 1024 * 1024 && !isBinary(full)
}

// Text files the agent left behind, minus build outputs and the harness itself.
// bin/ is build output next to a .NET project, but source in dune / Go / Dart layouts.
const isOutputDir = (name, dotnet) => SKIP_DIRS.has(name) || /^(\.|cmake-build)/.test(name) || (name === 'bin' && dotnet)

export function solutionFiles(dir, prefix = '') {
  const out = []
  const entries = readdirSync(dir, { withFileTypes: true })
  // A nested git checkout (forge install, git submodules) is a fetched dependency, not solution code.
  if (prefix && entries.some((e) => e.name === '.git')) return out
  const dotnet = entries.some((e) => e.isFile() && /\.(cs|fs|vb)proj$/.test(e.name))
  for (const e of entries) {
    const rel = prefix ? `${prefix}/${e.name}` : e.name
    const full = join(dir, e.name)
    if (e.isDirectory() && !isOutputDir(e.name, dotnet)) out.push(...solutionFiles(full, rel))
    else if (e.isFile() && keepFile(full, e.name)) out.push(rel)
  }
  return out.sort()
}

// Files whose tokens count as "the code": sources and manifests, not lockfiles or vendored blobs.
export function isCounted(dir, rel) {
  const name = basename(rel)
  if (LOCKFILES.has(name) || name.startsWith('.')) return false
  if (!COUNTED_EXT.has(extname(name)) && !COUNTED_NAMES.has(name)) return false
  return statSync(join(dir, rel)).size <= MAX_SOURCE_BYTES
}

export function copyFiles(from, to, files) {
  for (const rel of files) {
    mkdirSync(dirname(join(to, rel)), { recursive: true })
    copyFileSync(join(from, rel), join(to, rel))
  }
}

// Environment for nested `claude` runs: the logged-in Claude Code account, not a raw API key.
// The CLI never updates itself mid-run: every agent of a round runs the same version.
export function claudeEnv() {
  const env = { ...process.env, DISABLE_AUTOUPDATER: '1' }
  if (!process.env.TKN_USE_API_KEY) delete env.ANTHROPIC_API_KEY
  return env
}

export function firstLine(cmd) {
  const r = spawnSync(cmd[0], cmd.slice(1), { encoding: 'utf8' })
  return `${r.stdout}${r.stderr}`.split('\n')[0].trim()
}

// Kills processes an agent or a build left running inside dir (test servers, build daemons).
export function killStragglers(dir) {
  const root = realpathSync(dir)
  const out = spawnSync('lsof', ['-d', 'cwd', '-Fpn'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).stdout ?? ''
  let pid = 0
  for (const line of out.split('\n')) {
    if (line.startsWith('p')) pid = Number(line.slice(1))
    // Whole path components only: skillgen/c must not match skillgen/cpp.
    else if (line.startsWith('n') && `${line.slice(1)}/`.startsWith(`${root}/`) && pid !== process.pid) {
      try {
        process.kill(pid, 'SIGKILL')
      } catch {
        // already gone
      }
    }
  }
}

export function duBytes(path) {
  if (!existsSync(path)) return 0
  const r = spawnSync('du', ['-sk', path], { encoding: 'utf8' })
  return Number(r.stdout.split('\t')[0]) * 1024
}

export function parseArgs(argv, defaults) {
  const out = { ...defaults }
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith('--')) continue
    const key = argv[i].slice(2)
    const next = argv[i + 1]
    out[key] = next && !next.startsWith('--') ? argv[++i] : true
  }
  return out
}

export const list = (v, all) => (v ? String(v).split(',') : Object.keys(all))

export async function pool(items, jobs, fn) {
  const queue = [...items]
  const worker = async () => {
    while (queue.length) await fn(queue.shift())
  }
  await Promise.all(Array.from({ length: Math.min(jobs, items.length) }, worker))
}
