// Disk over an edit-rebuild loop, per language, with no agent: the baseline's working kvhttp solution (rep 1)
// is rebuilt with its own build.sh after a one-line comment edit, N times. After each build we record the
// project's build output (target/, .zig-cache, build/...), the global caches (isolated in a sandbox home as in
// verify: CARGO_HOME, GOCACHE, the Zig global cache, ~/.gradle, ...) and the build time. Rust's artifacts are
// replaced on rebuild; Zig's cache keeps every build. node bench/growth.mjs [--cycles 20] [--langs zig,rust] [--force]
import { spawnSync } from 'node:child_process'
import { appendFileSync, existsSync, rmSync, statSync } from 'node:fs'
import { extname, join } from 'node:path'
import { MAIN_LANGS, WORK, runDir } from './config.mjs'
import { workingSolution } from './agent.mjs'
import { copyFiles, duBytes, isCounted, killStragglers, list, parseArgs, removeTree, solutionFiles, writeJson } from './lib.mjs'
import { sandboxEnv } from './verify.mjs'

const args = parseArgs(process.argv.slice(2), { cycles: '20' })
const TASK = 'kvhttp'
// Line-comment syntax by source extension; OCaml has block comments only.
const COMMENT = {
  '//': ['.rs', '.go', '.zig', '.odin', '.c', '.h', '.cc', '.cpp', '.hpp', '.swift', '.java', '.kt', '.cs', '.js', '.mjs', '.ts', '.s'],
  '#': ['.py', '.nim'],
  '--': ['.hs'],
  ';': ['.clj'],
}
const commentFor = (ext) => (ext === '.ml' ? (i) => `\n(* edit ${i} *)\n` : (i) => `\n${Object.keys(COMMENT).find((c) => COMMENT[c].includes(ext))} edit ${i}\n`)
const editable = (f) => extname(f) === '.ml' || Object.values(COMMENT).flat().includes(extname(f))

// The file a developer would be editing: the largest source file of the solution.
function mainSource(dir) {
  const files = solutionFiles(dir).filter((f) => isCounted(dir, f) && editable(f))
  return files.sort((a, b) => statSync(join(dir, b)).size - statSync(join(dir, a)).size)[0]
}

function build(dir, env) {
  const t0 = performance.now()
  const r = spawnSync('bash', ['build.sh'], { cwd: dir, env, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, timeout: 20 * 60 * 1000 })
  killStragglers(dir)
  return { ok: r.status === 0, secs: Number(((performance.now() - t0) / 1000).toFixed(2)) }
}

function measure(lang) {
  const out = join(runDir(lang, TASK, 1), 'growth.json')
  if (existsSync(out) && !args.force) return
  const dir = join(WORK, 'growth', lang)
  const home = `${dir}.home`
  rmSync(dir, { recursive: true, force: true })
  removeTree(home)
  const src = workingSolution(lang, TASK, 1)
  copyFiles(src, dir, solutionFiles(src))
  const file = mainSource(dir)
  const sourceBytes = duBytes(dir)
  const env = sandboxEnv(home)
  const series = []
  for (let i = 0; i <= Number(args.cycles); i++) {
    if (i > 0) appendFileSync(join(dir, file), commentFor(extname(file))(i))
    series.push({ cycle: i, ...build(dir, env), projectBytes: Math.max(0, duBytes(dir) - sourceBytes), cacheBytes: duBytes(home) })
  }
  writeJson(out, { task: TASK, file, cycles: Number(args.cycles), series })
  const [first, last] = [series[0], series.at(-1)]
  console.log(`${lang}: project ${(first.projectBytes / 1e6).toFixed(1)} → ${(last.projectBytes / 1e6).toFixed(1)} MB, caches ${(first.cacheBytes / 1e6).toFixed(1)} → ${(last.cacheBytes / 1e6).toFixed(1)} MB, ok ${series.filter((s) => s.ok).length}/${series.length}`)
  rmSync(dir, { recursive: true, force: true })
  removeTree(home)
}

for (const lang of list(args.langs, Object.fromEntries(MAIN_LANGS.map((l) => [l, true])))) measure(lang)
