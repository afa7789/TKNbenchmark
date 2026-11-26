// Swarm study (TKN_ARM=swarm): a task built by a team of agents in one git repository. A lead sets up the
// project (for notes, also its core), three workers do one part each in parallel, each in its own git
// worktree, and an integrator merges the branches. Records one agent.json per case like run.mjs, so verify,
// count and aggregate work unchanged.
// - suite: the solo control is the base arm's run.mjs --tasks suite.
// - notes: the solo control runs here too, alternating with the team, one case at a time; caches start cold
//   in every case (Cargo, Go, Zig caches in a per-case directory), and disk is sampled every 15 s.
// TKN_ARM=swarm node bench/swarm.mjs [--task suite|notes] [--langs zig,rust] [--reps 3] [--force] [--merges]
// --merges: (re)write merge.json for recorded cases whose repository is still in WORK.
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { ARM, BASE_RUNS, EFFORT, MODEL, ROOT, SWARM, TOOLS, WORK, prompt, runDir, runId, swarmPrompt } from './config.mjs'
import { baselineToolchains, prepareWorkdir, runAgent } from './agent.mjs'
import { SKIP_DIRS, copyFiles, duBytes, parseArgs, removeTree, solutionFiles, writeJson } from './lib.mjs'
import { parseTranscript } from './transcript.mjs'

if (ARM !== 'swarm') throw new Error('run with TKN_ARM=swarm')
const args = parseArgs(process.argv.slice(2), { task: 'suite', reps: '3', langs: 'zig,rust,go,c,odin' })
const TASK = String(args.task)
const CFG = SWARM[TASK]
const SUBS = CFG.subs
const versions = baselineToolchains()
// Agents commit as a neutral identity; nothing here is pushed anywhere.
const GIT_ENV = { GIT_AUTHOR_NAME: 'agent', GIT_AUTHOR_EMAIL: 'agent@localhost', GIT_COMMITTER_NAME: 'agent', GIT_COMMITTER_EMAIL: 'agent@localhost' }
const SAMPLE_MS = 15_000

// The agents' environment for one case: git identity, and with cold caches the package and build caches in a
// directory of the case's own (HOME stays, so the agent keeps its login).
function caseCli(cacheDir) {
  const caches = CFG.cold
    ? { CARGO_HOME: join(cacheDir, 'cargo'), GOPATH: join(cacheDir, 'go'), GOMODCACHE: join(cacheDir, 'go', 'pkg', 'mod'), GOCACHE: join(cacheDir, 'go-build'), GOTOOLCHAIN: 'local', ZIG_GLOBAL_CACHE_DIR: join(cacheDir, 'zig') }
    : {}
  return { tools: TOOLS, args: [], env: { ...GIT_ENV, ...caches } }
}

function git(dir, ...argv) {
  const r = spawnSync('git', argv, { cwd: dir, env: { ...process.env, ...GIT_ENV }, encoding: 'utf8' })
  if (r.status !== 0) throw new Error(`git ${argv.join(' ')} in ${dir}: ${r.stderr}`)
  return r.stdout
}
function commitAll(dir, msg) {
  git(dir, 'add', '-A')
  git(dir, 'commit', '-q', '--allow-empty', '-m', msg)
}

// Disk every SAMPLE_MS while agents work: each working directory and the case's caches.
function sampler(dirs, cacheDir) {
  const t0 = Date.now()
  const series = []
  const take = () => series.push({ s: Math.round((Date.now() - t0) / 1000), dirs: dirs().map(duBytes), cacheBytes: duBytes(cacheDir) })
  take()
  const timer = setInterval(take, SAMPLE_MS)
  return () => {
    clearInterval(timer)
    take()
    return { series, peakBytes: Math.max(...series.map((x) => x.dirs.reduce((a, b) => a + b, 0))), peakCacheBytes: Math.max(...series.map((x) => x.cacheBytes)) }
  }
}

// Merge conflicts measured by the harness, not read from an agent's output: merge the workers' branches
// one by one in git's object store (merge-tree; no working tree is touched) and count conflicted files.
function trialMerge(root) {
  const files = []
  let head = SUBS[0]
  for (const s of SUBS.slice(1)) {
    const r = spawnSync('git', ['merge-tree', '--write-tree', '--name-only', head, s], { cwd: root, encoding: 'utf8' })
    const [tree, ...rest] = r.stdout.split('\n')
    if (r.status === 1) files.push(...rest.slice(0, rest.indexOf('')).map((f) => `${s}:${f}`))
    head = git(root, 'commit-tree', tree, '-p', head, '-p', s, '-m', `trial ${s}`).trim()
  }
  return { conflictedFiles: files.length, files }
}

async function phase(dir, name, lang, out, cli) {
  const transcript = join(out, 'phases', name, 'transcript.jsonl')
  mkdirSync(dirname(transcript), { recursive: true })
  const t0 = Date.now()
  await runAgent(dir, swarmPrompt(name, lang, versions[lang], TASK), transcript, cli)
  return { name, ms: Date.now() - t0, ...parseTranscript(readFileSync(transcript, 'utf8')) }
}

// Totals over the phases, in the fields run.mjs records for one agent.
const USAGE = ['input', 'output', 'cacheRead', 'cacheWrite']
const COUNTS = ['turns', 'builds', 'compileErrors', 'stdlibReads', 'checkRuns', 'toolErrors']
const total = (ps, f) => ps.reduce((s, p) => s + (f(p) ?? 0), 0)

function combine(ps, last) {
  const tools = {}
  for (const p of ps) for (const [k, n] of Object.entries(p.tools)) tools[k] = (tools[k] ?? 0) + n
  return {
    ...Object.fromEntries(COUNTS.map((k) => [k, total(ps, (p) => p[k])])),
    usage: Object.fromEntries(USAGE.map((k) => [k, total(ps, (p) => p.usage[k])])),
    costUsd: total(ps, (p) => p.costUsd),
    tools,
    models: [...new Set(ps.flatMap((p) => p.models))],
    finished: ps.every((p) => p.finished),
    terminalReason: last.terminalReason,
    firstCheckPass: last.firstCheckPass,
    lastCheck: last.lastCheck,
    reply: last.reply,
    skillsOffered: [],
  }
}

// A fresh repository: the task's workdir, each part's examples (and the lead's), build outputs ignored.
async function setUp(root, lang, rep) {
  await prepareWorkdir(TASK, root, lang, rep)
  const { visible } = await import(join(ROOT, 'bench', 'tasks', TASK, 'cases.mjs'))
  for (const s of [...SUBS, CFG.lead].filter(Boolean)) writeFileSync(join(root, `cases-${s}.json`), JSON.stringify(visible(lang, s), null, 1))
  writeFileSync(join(root, '.gitignore'), [...[...SKIP_DIRS].map((d) => `${d}/`), '/app', '*.o', '*.db'].join('\n') + '\n')
  git(root, 'init', '-q', '-b', 'main')
  commitAll(root, 'spec')
}

// The lead may have created the branches, or worktrees, itself: keep its work on main and start each worker
// on a fresh branch from it.
function addWorktrees(root, trees) {
  git(root, 'checkout', '-q', '-B', 'main')
  const self = realpathSync(root)
  for (const l of git(root, 'worktree', 'list', '--porcelain').split('\n')) {
    if (l.startsWith('worktree ') && realpathSync(l.slice(9)) !== self) git(root, 'worktree', 'remove', '--force', l.slice(9))
  }
  const branches = git(root, 'branch', '--format=%(refname:short)').split('\n')
  for (const s of SUBS) if (branches.includes(s)) git(root, 'branch', '-D', s)
  SUBS.forEach((s, i) => git(root, 'worktree', 'add', '-q', '-b', s, trees[i]))
}

function fresh(...dirs) {
  for (const d of dirs) removeTree(d)
}

async function teamCell(lang, rep) {
  const out = runDir(lang, TASK, rep)
  if (existsSync(join(out, 'agent.json')) && !args.force) return
  const id = runId(lang, TASK, rep)
  const [root, cacheDir] = [join(WORK, 'swarm', id), join(WORK, 'caches', `${id}-team`)]
  const trees = SUBS.map((s) => `${root}-${s}`)
  fresh(root, cacheDir, ...trees, out)
  await setUp(root, lang, rep)
  const cli = caseCli(cacheDir)
  console.log(`▶ ${id} (team)`)
  const t0 = Date.now()
  const stop = sampler(() => [root, ...trees.filter(existsSync)], cacheDir)
  const lead = await phase(root, 'lead', lang, out, cli)
  commitAll(root, 'skeleton')
  addWorktrees(root, trees)
  const workers = await Promise.all(SUBS.map((s, i) => phase(trees[i], s, lang, out, cli)))
  // Disk at the end of the parallel work: each worktree with its own build outputs.
  const worktreeBytes = trees.map(duBytes)
  SUBS.forEach((s, i) => commitAll(trees[i], s))
  const merge = trialMerge(root)
  const integrate = await phase(root, 'integrate', lang, out, cli)
  commitAll(root, 'integrated')
  const disk = stop()
  const wallMs = Date.now() - t0
  const phases = [lead, ...workers, integrate]
  for (const d of trees) git(root, 'worktree', 'remove', '--force', d)
  if (phases.some((p) => p.terminalReason === 'api_error')) return console.log(`✖ ${id} API error: not recorded, rerun later.`)
  for (const s of [...SUBS, CFG.lead].filter(Boolean)) rmSync(join(root, `cases-${s}.json`), { force: true })
  const files = solutionFiles(root)
  copyFiles(root, join(out, 'solution'), files)
  const summary = phases.map((p) => ({ name: p.name, ms: p.ms, costUsd: p.costUsd, turns: p.turns, output: p.usage.output }))
  const swarm = { phases: summary, agentMs: total(phases, (p) => p.ms), worktreeBytes, mainBytes: duBytes(root), disk }
  writeJson(join(out, 'merge.json'), merge)
  writeJson(join(out, 'agent.json'), { id, lang, task: TASK, rep, arm: ARM, model: MODEL, effort: EFFORT, files, ...combine(phases, integrate), durationMs: wallMs, wallMs, swarm })
  console.log(`✔ ${id} team $${swarm.phases.reduce((s, p) => s + p.costUsd, 0).toFixed(2)} wall ${Math.round(wallMs / 1000)}s conflicted ${merge.conflictedFiles} peak disk ${Math.round(disk.peakBytes / 1e6)}MB + caches ${Math.round(disk.peakCacheBytes / 1e6)}MB`)
}

// The solo control of a team case: the base arm's prompt in one directory, with the same caches and sampler.
async function soloCell(lang, rep) {
  const out = join(BASE_RUNS, lang, TASK, `r${rep}`)
  if (existsSync(join(out, 'agent.json')) && !args.force) return
  const id = runId(lang, TASK, rep)
  const [dir, cacheDir] = [join(WORK, 'solo', id), join(WORK, 'caches', `${id}-solo`)]
  fresh(dir, cacheDir, out)
  await prepareWorkdir(TASK, dir, lang, rep)
  mkdirSync(out, { recursive: true })
  console.log(`▶ ${id} (solo)`)
  const t0 = Date.now()
  const stop = sampler(() => [dir], cacheDir)
  const transcript = join(out, 'transcript.jsonl')
  const exitCode = await runAgent(dir, prompt(TASK, lang, versions[lang]), transcript, caseCli(cacheDir))
  const disk = stop()
  const metrics = parseTranscript(readFileSync(transcript, 'utf8'))
  if (metrics.terminalReason === 'api_error') return console.log(`✖ ${id} API error: not recorded, rerun later.`)
  const files = solutionFiles(dir)
  copyFiles(dir, join(out, 'solution'), files)
  writeJson(join(out, 'agent.json'), { id, lang, task: TASK, rep, arm: 'base', model: MODEL, effort: EFFORT, exitCode, wallMs: Date.now() - t0, files, ...metrics, disk })
  console.log(`✔ ${id} solo $${metrics.costUsd?.toFixed(2)} wall ${Math.round((Date.now() - t0) / 1000)}s peak disk ${Math.round(disk.peakBytes / 1e6)}MB + caches ${Math.round(disk.peakCacheBytes / 1e6)}MB`)
}

// Backfill: measure the merges of cases already recorded, from their repositories still in WORK.
if (args.merges) {
  for (let rep = 1; rep <= Number(args.reps); rep++) {
    for (const lang of String(args.langs).split(',')) {
      const root = join(WORK, 'swarm', runId(lang, TASK, rep))
      if (!existsSync(join(root, '.git'))) continue
      const merge = trialMerge(root)
      writeJson(join(runDir(lang, TASK, rep), 'merge.json'), merge)
      console.log(`${runId(lang, TASK, rep)}: ${JSON.stringify(merge)}`)
    }
  }
  process.exit(0)
}

// One case at a time (a team's three workers run in parallel). With a solo control here, solo and team
// alternate which goes first. A case that breaks is reported and left for the next pass.
const report = (lang, rep, mode) => (e) => console.log(`✖ ${runId(lang, TASK, rep)} (${mode}): ${e.message.split('\n')[0]}`)
const langs = String(args.langs).split(',')
for (let rep = 1; rep <= Number(args.reps); rep++) {
  for (const [i, lang] of langs.entries()) {
    const cells = [['team', teamCell], ...(CFG.solo ? [['solo', soloCell]] : [])]
    if ((rep + i) % 2) cells.reverse()
    for (const [mode, cell] of cells) await cell(lang, rep).catch(report(lang, rep, mode))
  }
}
