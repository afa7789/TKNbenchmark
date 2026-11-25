// Round 3 (backend): cold build from a clean copy with sandboxed caches, then the hidden suite.
// One run at a time. node bench/verify.mjs [--force]
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, copyFileSync, writeFileSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ROOT, RUNS, WORK, TASKS } from './config.mjs'
import { copyFiles, duBytes, killStragglers, parseArgs, readJson, solutionFiles, writeJson } from './lib.mjs'

export const builtDir = (id) => join(WORK, 'built', id)

function sandboxEnv(home) {
  mkdirSync(home, { recursive: true })
  return {
    ...process.env,
    HOME: home,
    XDG_CACHE_HOME: join(home, '.cache'),
    CARGO_HOME: join(home, '.cargo'),
    RUSTUP_HOME: process.env.RUSTUP_HOME ?? join(homedir(), '.rustup'),
    GOPATH: join(home, 'go'),
    GOCACHE: join(home, 'go-build'),
    GOMODCACHE: join(home, 'go', 'pkg', 'mod'),
    GOTOOLCHAIN: 'local',
    ZIG_GLOBAL_CACHE_DIR: join(home, 'zig'),
    NIMBLE_DIR: join(home, '.nimble'),
    GRADLE_USER_HOME: join(home, '.gradle'),
    MAVEN_OPTS: `-Dmaven.repo.local=${join(home, '.m2', 'repository')}`,
    NUGET_PACKAGES: join(home, '.nuget', 'packages'),
    DOTNET_CLI_HOME: home,
    OPAMROOT: join(home, '.opam'),
    CABAL_DIR: join(home, '.cabal'),
    ELAN_HOME: process.env.ELAN_HOME ?? join(homedir(), '.elan'),
    JULIA_DEPOT_PATH: join(home, '.julia'),
    R_LIBS_USER: join(home, 'R'),
    CLJ_CONFIG: join(home, '.clojure'),
    GITLIBS: join(home, '.gitlibs'),
  }
}

function hiddenTests(dir) {
  const r = spawnSync('node', ['check.mjs', '--no-build', '--json'], { cwd: dir, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 10 * 60 * 1000 })
  const last = (r.stdout ?? '').trim().split('\n').at(-1)
  try {
    return JSON.parse(last)
  } catch {
    return { pass: 0, total: 0, results: [], error: (r.stderr ?? '').slice(-2000) }
  }
}

function jarBytes(dir) {
  let total = 0
  for (const e of readdirSync(dir, { withFileTypes: true, recursive: true })) {
    if (e.isFile() && e.name.endsWith('.jar') && !e.parentPath.includes('.gradle')) total += statSync(join(e.parentPath, e.name)).size
  }
  return total
}

// Native binary size, or the jars behind a JVM launcher script.
function artifactBytes(dir) {
  const app = join(dir, 'app')
  if (!existsSync(app)) return 0
  const isScript = !readFileSync(app).subarray(0, 4096).includes(0)
  return isScript ? jarBytes(dir) + statSync(app).size : statSync(app).size
}

// macOS scans a freshly built executable on its first launch, which can take seconds for large
// binaries. One throwaway launch keeps that out of the tests' startup deadline.
function warmUp(dir, task) {
  spawnSync(join(dir, 'app'), TASKS[task].kind === 'http' ? ['0'] : [], { cwd: dir, input: '', timeout: 5000 })
  killStragglers(dir)
}

function testBuild(dir, task, buildOk, total) {
  if (!buildOk) return { pass: 0, total, results: [] }
  if (['stdio', 'http'].includes(TASKS[task].kind)) warmUp(dir, task)
  return hiddenTests(dir)
}

// Builds and tests one solution. Keeps the built tree at builtDir(id) for the perf round.
export async function verifySolution(solDir, task, id, lang) {
  const dir = join(WORK, 'verify', id)
  const home = `${dir}.home`
  rmSync(dir, { recursive: true, force: true })
  rmSync(home, { recursive: true, force: true })
  copyFiles(solDir, dir, solutionFiles(solDir))
  copyFileSync(join(ROOT, 'bench', 'harness', 'check.mjs'), join(dir, 'check.mjs'))
  const { hidden } = await import(join(ROOT, 'bench', 'tasks', task, 'cases.mjs'))
  writeFileSync(join(dir, 'cases.json'), JSON.stringify(hidden(lang)))
  const sourceBytes = duBytes(dir)

  const t0 = performance.now()
  const b = spawnSync('bash', ['build.sh'], { cwd: dir, env: sandboxEnv(home), encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, timeout: 20 * 60 * 1000 })
  const buildSecs = (performance.now() - t0) / 1000
  const needsApp = ['stdio', 'http'].includes(TASKS[task].kind)
  const buildOk = b.status === 0 && (!needsApp || existsSync(join(dir, 'app')))
  const tests = testBuild(dir, task, buildOk, hidden(lang).cases.length)
  const projectBytes = Math.max(0, duBytes(dir) - sourceBytes)
  const cacheBytes = duBytes(home)
  killStragglers(dir)
  const out = {
    buildOk,
    buildSecs: Number(buildSecs.toFixed(2)),
    buildLog: buildOk ? '' : `${b.stdout ?? ''}${b.stderr ?? ''}`.slice(-3000),
    binaryBytes: buildOk ? artifactBytes(dir) : 0,
    projectBytes,
    cacheBytes,
    footprintBytes: projectBytes + cacheBytes,
    pass: tests.pass,
    total: tests.total,
    solved: buildOk && tests.total > 0 && tests.pass === tests.total,
    cases: tests.results.map(({ name, ok, ms, why }) => ({ name, ok, ms, why: why ? String(why).slice(0, 400) : undefined })),
  }
  rmSync(home, { recursive: true, force: true })
  rmSync(builtDir(id), { recursive: true, force: true })
  if (buildOk) {
    mkdirSync(join(WORK, 'built'), { recursive: true })
    renameSync(dir, builtDir(id))
  } else rmSync(dir, { recursive: true, force: true })
  console.log(`${id}: build=${buildOk} ${out.buildSecs}s footprint=${(out.footprintBytes / 1e6).toFixed(1)}MB tests=${out.pass}/${out.total}`)
  return out
}

function runsToVerify(force, tasks) {
  const found = []
  for (const lang of readdirSync(RUNS, { withFileTypes: true }).filter((e) => e.isDirectory())) {
    for (const task of readdirSync(join(RUNS, lang.name))) {
      if (TASKS[task]?.kind === 'static' || (tasks && !tasks.includes(task))) continue
      for (const rep of readdirSync(join(RUNS, lang.name, task))) found.push(join(RUNS, lang.name, task, rep))
    }
  }
  return found.filter((r) => existsSync(join(r, 'agent.json')) && (force || !existsSync(join(r, 'verify.json'))))
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = parseArgs(process.argv.slice(2), {})
  for (const run of runsToVerify(args.force, args.tasks && String(args.tasks).split(','))) {
    const meta = readJson(join(run, 'agent.json'))
    writeJson(join(run, 'verify.json'), await verifySolution(join(run, 'solution'), meta.task, meta.id, meta.lang))
  }
}
