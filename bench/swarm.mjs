// Swarm study (TKN_ARM=swarm): the suite task built by a team of agents in one git repository. A lead sets
// up the skeleton, three workers implement wordfreq, lru and calc in parallel, each in its own git worktree,
// and an integrator merges the branches. The solo control is the base arm's suite run (run.mjs --tasks
// suite). Records one agent.json per case like run.mjs, so verify, count and aggregate work unchanged.
// TKN_ARM=swarm node bench/swarm.mjs [--langs zig,rust] [--reps 3] [--force] [--merges]
// --merges: (re)write merge.json for recorded cases whose repository is still in WORK.
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { ARM, EFFORT, MODEL, ROOT, SWARM_SUBS, TOOLS, WORK, runDir, runId, swarmPrompt } from './config.mjs'
import { baselineToolchains, prepareWorkdir, runAgent } from './agent.mjs'
import { SKIP_DIRS, copyFiles, duBytes, parseArgs, solutionFiles, writeJson } from './lib.mjs'
import { parseTranscript } from './transcript.mjs'

if (ARM !== 'swarm') throw new Error('run with TKN_ARM=swarm')
const args = parseArgs(process.argv.slice(2), { reps: '3', langs: 'zig,rust,go,c,odin' })
const versions = baselineToolchains()
// Agents commit as a neutral identity; nothing here is pushed anywhere.
const GIT_ENV = { GIT_AUTHOR_NAME: 'agent', GIT_AUTHOR_EMAIL: 'agent@localhost', GIT_COMMITTER_NAME: 'agent', GIT_COMMITTER_EMAIL: 'agent@localhost' }
const CLI = { tools: TOOLS, args: [], env: GIT_ENV }

function git(dir, ...argv) {
  const r = spawnSync('git', argv, { cwd: dir, env: { ...process.env, ...GIT_ENV }, encoding: 'utf8' })
  if (r.status !== 0) throw new Error(`git ${argv.join(' ')} in ${dir}: ${r.stderr}`)
  return r.stdout
}
function commitAll(dir, msg) {
  git(dir, 'add', '-A')
  git(dir, 'commit', '-q', '--allow-empty', '-m', msg)
}

// Merge conflicts measured by the harness, not read from an agent's output: merge the workers' branches
// one by one in git's object store (merge-tree; no working tree is touched) and count conflicted files.
function trialMerge(root) {
  const files = []
  let head = SWARM_SUBS[0]
  for (const s of SWARM_SUBS.slice(1)) {
    const r = spawnSync('git', ['merge-tree', '--write-tree', '--name-only', head, s], { cwd: root, encoding: 'utf8' })
    const [tree, ...rest] = r.stdout.split('\n')
    if (r.status === 1) files.push(...rest.slice(0, rest.indexOf('')).map((f) => `${s}:${f}`))
    head = git(root, 'commit-tree', tree, '-p', head, '-p', s, '-m', `trial ${s}`).trim()
  }
  return { conflictedFiles: files.length, files }
}

async function phase(dir, name, lang, out) {
  const transcript = join(out, 'phases', name, 'transcript.jsonl')
  mkdirSync(dirname(transcript), { recursive: true })
  const t0 = Date.now()
  await runAgent(dir, swarmPrompt(name, lang, versions[lang]), transcript, CLI)
  return { name, ms: Date.now() - t0, text: readFileSync(transcript, 'utf8'), ...parseTranscript(readFileSync(transcript, 'utf8')) }
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

// A fresh repository: the suite's workdir, each subcommand's examples, build outputs ignored.
async function setUp(root, lang, rep) {
  await prepareWorkdir('suite', root, lang, rep)
  const { visible } = await import(join(ROOT, 'bench', 'tasks', 'suite', 'cases.mjs'))
  for (const s of SWARM_SUBS) writeFileSync(join(root, `cases-${s}.json`), JSON.stringify(visible(lang, s), null, 1))
  writeFileSync(join(root, '.gitignore'), [...[...SKIP_DIRS].map((d) => `${d}/`), '/app', '*.o'].join('\n') + '\n')
  git(root, 'init', '-q', '-b', 'main')
  commitAll(root, 'spec')
}

// The lead may have created the branches, or worktrees, itself: keep its skeleton on main and start each
// worker on a fresh branch from it.
function addWorktrees(root, trees) {
  git(root, 'checkout', '-q', '-B', 'main')
  const self = realpathSync(root)
  for (const l of git(root, 'worktree', 'list', '--porcelain').split('\n')) {
    if (l.startsWith('worktree ') && realpathSync(l.slice(9)) !== self) git(root, 'worktree', 'remove', '--force', l.slice(9))
  }
  const branches = git(root, 'branch', '--format=%(refname:short)').split('\n')
  for (const s of SWARM_SUBS) if (branches.includes(s)) git(root, 'branch', '-D', s)
  SWARM_SUBS.forEach((s, i) => git(root, 'worktree', 'add', '-q', '-b', s, trees[i]))
}

async function swarmCell(lang, rep) {
  const out = runDir(lang, 'suite', rep)
  if (existsSync(join(out, 'agent.json')) && !args.force) return
  const id = runId(lang, 'suite', rep)
  const root = join(WORK, 'swarm', id)
  const trees = SWARM_SUBS.map((s) => `${root}-${s}`)
  for (const d of [root, ...trees]) rmSync(d, { recursive: true, force: true })
  await setUp(root, lang, rep)
  rmSync(out, { recursive: true, force: true })
  console.log(`▶ ${id} (swarm)`)
  const t0 = Date.now()
  const lead = await phase(root, 'lead', lang, out)
  commitAll(root, 'skeleton')
  addWorktrees(root, trees)
  const workers = await Promise.all(SWARM_SUBS.map((s, i) => phase(trees[i], s, lang, out)))
  // Disk while the team works: each worktree with its own build outputs (target/, .zig-cache, ...).
  const worktreeBytes = trees.map(duBytes)
  SWARM_SUBS.forEach((s, i) => commitAll(trees[i], s))
  const merge = trialMerge(root)
  const integrate = await phase(root, 'integrate', lang, out)
  commitAll(root, 'integrated')
  const wallMs = Date.now() - t0
  const phases = [lead, ...workers, integrate]
  for (const d of trees) git(root, 'worktree', 'remove', '--force', d)
  if (phases.some((p) => p.terminalReason === 'api_error')) return console.log(`✖ ${id} API error: not recorded, rerun later.`)
  for (const s of SWARM_SUBS) rmSync(join(root, `cases-${s}.json`), { force: true })
  const files = solutionFiles(root)
  copyFiles(root, join(out, 'solution'), files)
  const summary = phases.map((p) => ({ name: p.name, ms: p.ms, costUsd: p.costUsd, turns: p.turns, output: p.usage.output }))
  const swarm = { phases: summary, agentMs: total(phases, (p) => p.ms), worktreeBytes, mainBytes: duBytes(root) }
  writeJson(join(out, 'merge.json'), merge)
  writeJson(join(out, 'agent.json'), { id, lang, task: 'suite', rep, arm: ARM, model: MODEL, effort: EFFORT, files, ...combine(phases, integrate), durationMs: wallMs, wallMs, swarm })
  console.log(`✔ ${id} cost=$${swarm.phases.reduce((s, p) => s + p.costUsd, 0).toFixed(2)} wall=${Math.round(wallMs / 1000)}s conflicted files=${merge.conflictedFiles} worktrees=${worktreeBytes.map((b) => `${Math.round(b / 1e6)}MB`).join('/')}`)
}

// Backfill: measure the merges of cases already recorded, from their repositories still in WORK.
if (args.merges) {
  for (let rep = 1; rep <= Number(args.reps); rep++) {
    for (const lang of String(args.langs).split(',')) {
      const root = join(WORK, 'swarm', runId(lang, 'suite', rep))
      if (!existsSync(join(root, '.git'))) continue
      const merge = trialMerge(root)
      writeJson(join(runDir(lang, 'suite', rep), 'merge.json'), merge)
      console.log(`${runId(lang, 'suite', rep)}: ${JSON.stringify(merge)}`)
    }
  }
  process.exit(0)
}

// One team at a time: its three workers already run in parallel.
// A case that breaks is reported and left for the next pass; it does not stop the others.
for (let rep = 1; rep <= Number(args.reps); rep++) {
  for (const lang of String(args.langs).split(',')) await swarmCell(lang, rep).catch((e) => console.log(`✖ ${runId(lang, 'suite', rep)}: ${e.message.split('\n')[0]}`))
}
