// Collects runs/ into public/data/results.json (+ one solutions/<id>.json per run for the code viewer).
// node bench/aggregate.mjs          build the data
// node bench/aggregate.mjs --check  validate the committed data (CI smoke)
import { existsSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT, RUNS, LANGS, FRONTENDS, TASKS, TRACKS, MODEL, EFFORT, MAIN_LANGS, ARM, SKILLS, PRICE, PORT_FROM } from './config.mjs'
import { isCounted, readJson, solutionFiles, spearman, writeJson } from './lib.mjs'
import { detectDeps } from './deps.mjs'

// The published run writes public/data; another arm writes public/data/<arm> and compares itself with it.
const BASE_OUT = join(ROOT, 'public', 'data')
const OUT = ARM === 'base' ? BASE_OUT : join(BASE_OUT, ARM)
const EXTERNAL = {
  title: 'We Measured the LLM Token Cost of 5 Frontend Frameworks: Angular Costs 38% More Than Svelte',
  author: 'Andrey Kucherenko (HackerNoon, "The Tokenomics of Web Development", part 1)',
  url: 'https://hackernoon.com/we-measured-the-llm-token-cost-of-5-frontend-frameworks-angular-costs-38percent-more-than-svelte',
  tokenizer: 'cl100k_base (tiktoken)',
  quote: 'Svelte ×1.000 · Vue ×1.115 · SolidJS ×1.196 · React ×1.254 · Angular ×1.381.',
  svelteTokens: 598,
  multipliers: { Svelte: 1, Vue: 1.115, SolidJS: 1.196, React: 1.254, Angular: 1.381 },
}

const opt = (p) => (existsSync(p) ? readJson(p) : null)
const nums = (xs) => xs.filter((x) => typeof x === 'number' && Number.isFinite(x))
const sum = (xs) => nums(xs).reduce((a, b) => a + b, 0)

function stats(xs) {
  const v = nums(xs).sort((a, b) => a - b)
  if (!v.length) return null
  const mid = v.length >> 1
  const median = v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2
  return { median, min: v[0], max: v.at(-1), n: v.length }
}

function collect() {
  const runs = []
  for (const lang of readdirSync(RUNS, { withFileTypes: true }).filter((e) => e.isDirectory())) {
    for (const task of readdirSync(join(RUNS, lang.name))) {
      for (const rep of readdirSync(join(RUNS, lang.name, task))) {
        const dir = join(RUNS, lang.name, task, rep)
        const agent = opt(join(dir, 'agent.json'))
        if (agent) runs.push({ dir, agent, verify: opt(join(dir, 'verify.json')), tokens: opt(join(dir, 'tokens.json')), perf: opt(join(dir, 'perf.json')), repair: opt(join(dir, 'repair.json')), devloop: opt(join(dir, 'devloop.json')), twins: opt(join(dir, 'perf-twins.json')), merge: opt(join(dir, 'merge.json')), growth: opt(join(dir, 'growth.json')) })
      }
    }
  }
  return runs.sort((a, b) => a.agent.id.localeCompare(b.agent.id))
}

// Copy fields out of an optional record: { newName: 'sourceField' }, missing → null.
const fields = (o, map) => Object.fromEntries(Object.entries(map).map(([to, from]) => [to, o?.[from] ?? null]))
const same = (...keys) => Object.fromEntries(keys.map((k) => [k, k]))

// Round 4: what it took to get a failed run to pass. works = passed in round 3 or after repair.
const NO_REPAIR = { fixed: null, costUsd: 0, attempts: [] }

function repairFields(a, v, found) {
  const rp = found ?? NO_REPAIR
  const works = v ? Boolean(v.solved || rp.fixed) : null
  return {
    ...fields(found, { fixed: 'fixed', repairCostUsd: 'costUsd', repairDurationS: 'durationS', repairOutput: 'output' }),
    repairAttempts: rp.attempts.length,
    repairLog: rp.attempts.map((x) => ({ n: x.n, costUsd: x.costUsd, durationS: x.durationS, output: x.usage.output, pass: x.pass, total: x.total, solved: x.solved })),
    works,
    costToGreenUsd: works ? a.costUsd + rp.costUsd : null,
  }
}

// Disk for N parallel worktrees: per-project artifacts are duplicated, global caches are shared.
const worktrees = (v, n) => (v ? n * v.projectBytes + v.cacheBytes : null)

// Peak disk sampled while the agent(s) worked: the solo control's own, or a swarm team's.
function diskFields(a) {
  const d = a.swarm?.disk ?? a.disk
  return { diskPeakBytes: d?.peakBytes ?? null, cachePeakBytes: d?.peakCacheBytes ?? null }
}

// One perf record's headline number: throughput for kvhttp, else wall time.
const perfValue = (p) => p?.rps ?? p?.wallMs ?? null

function publicRun({ agent: a, verify: v, tokens: t, perf: p, repair: rp, devloop: dl, twins: tw, merge: mg }) {
  return {
    ...fields(a, same('id', 'lang', 'task', 'rep', 'finished', 'terminalReason', 'costUsd', 'turns', 'usage', 'tools', 'builds', 'compileErrors', 'stdlibReads', 'checkRuns', 'firstCheckPass', 'models')),
    durationS: a.durationMs / 1000,
    // The harness's own clock around the agent(s): the one clock both solo runs and swarm teams have.
    wallS: a.wallMs / 1000,
    ...diskFields(a),
    apiS: a.apiMs / 1000,
    ...fields(v, same('solved', 'pass', 'total', 'buildOk', 'buildSecs', 'footprintBytes', 'projectBytes', 'cacheBytes', 'binaryBytes')),
    failures: (v?.cases ?? []).filter((c) => !c.ok).map((c) => ({ name: c.name, why: c.why })),
    ...fields(t, { codeTokens: 'opus', codeTokensCl100k: 'cl100k', codeChars: 'chars', codeLines: 'lines' }),
    fileTokens: t?.files ?? [],
    ...fields(p, { perfMs: 'wallMs', perfRps: 'rps', perfRssBytes: 'rssBytes' }),
    ...repairFields(a, v, rp),
    worktrees4Bytes: worktrees(v, 4),
    devloopTargetBytes: dl?.targetBytes ?? null,
    // Swarm arm: wall-clock vs summed agent time, disk of the workers' worktrees, merge conflicts.
    swarm: a.swarm ? { agentS: a.swarm.agentMs / 1000, worktreeBytes: sum(a.swarm.worktreeBytes), conflictedFiles: mg?.conflictedFiles, phases: a.swarm.phases } : null,
    // Paired perf (arms): the same session's timings of the baseline cases this run is compared with.
    twinPerf: tw ? Object.fromEntries(Object.entries(tw).map(([role, x]) => [role, perfValue(x)])) : null,
  }
}

function tallyBy(rs, key) {
  const out = {}
  for (const r of rs) out[key(r)] = (out[key(r)] ?? 0) + 1
  return out
}

function cellSummary(rs) {
  const s = (f) => stats(rs.map(f))
  return {
    n: rs.length,
    solved: rs.filter((r) => r.solved).length,
    works: rs.filter((r) => r.works).length,
    firstTry: rs.filter((r) => r.firstCheckPass).length,
    costToGreenUsd: s((r) => r.costToGreenUsd),
    deps: tallyBy(rs, (r) => r.deps.join(', ')),
    costUsd: s((r) => r.costUsd),
    output: s((r) => r.usage.output),
    turns: s((r) => r.turns),
    durationS: s((r) => r.durationS),
    compileErrors: s((r) => r.compileErrors),
    stdlibReads: s((r) => r.stdlibReads),
    codeTokens: s((r) => r.codeTokens),
    codeTokensCl100k: s((r) => r.codeTokensCl100k),
    buildSecs: s((r) => r.buildSecs),
    footprintBytes: s((r) => r.footprintBytes),
    projectBytes: s((r) => r.projectBytes),
    cacheBytes: s((r) => r.cacheBytes),
    worktrees4Bytes: s((r) => r.worktrees4Bytes),
    devloopTargetBytes: s((r) => r.devloopTargetBytes),
    binaryBytes: s((r) => r.binaryBytes),
    perfMs: s((r) => r.perfMs),
    perfRps: s((r) => r.perfRps),
    perfRssBytes: s((r) => r.perfRssBytes),
  }
}

const med = (cells, key) => sum(cells.map((c) => c[key]?.median))

function langSummary(cells, rs) {
  const solved = rs.filter((r) => r.solved).length
  return {
    n: rs.length,
    solved,
    works: rs.filter((r) => r.works).length,
    passRate: rs.length ? solved / rs.length : 0,
    repairCostUsd: sum(rs.map((r) => r.repairCostUsd)),
    firstTryRate: rs.length ? rs.filter((r) => r.firstCheckPass).length / rs.length : 0,
    costUsd: med(cells, 'costUsd'),
    costPerSolvedUsd: solved ? sum(rs.map((r) => r.costUsd)) / solved : null,
    output: med(cells, 'output'),
    turns: med(cells, 'turns'),
    durationS: med(cells, 'durationS'),
    compileErrors: med(cells, 'compileErrors'),
    stdlibReads: med(cells, 'stdlibReads'),
    codeTokens: med(cells, 'codeTokens'),
    codeTokensCl100k: med(cells, 'codeTokensCl100k'),
    buildSecs: med(cells, 'buildSecs'),
    footprintBytes: med(cells, 'footprintBytes'),
  }
}

function frontendSummary(rs) {
  const components = {}
  for (const r of rs) {
    for (const f of r.fileTokens) {
      const name = f.path.split('/').at(-1).replace(/\.(jsx|vue|svelte|js)$/, '')
      ;(components[name] ??= { opus: [], cl100k: [] }).opus.push(f.opus)
      components[name].cl100k.push(f.cl100k)
    }
  }
  return {
    n: rs.length,
    solved: rs.filter((r) => r.solved).length,
    works: rs.filter((r) => r.works).length,
    costUsd: stats(rs.map((r) => r.costUsd)),
    output: stats(rs.map((r) => r.usage.output)),
    codeTokens: stats(rs.map((r) => r.codeTokens)),
    codeTokensCl100k: stats(rs.map((r) => r.codeTokensCl100k)),
    components: Object.fromEntries(Object.entries(components).map(([k, v]) => [k, { opus: stats(v.opus), cl100k: stats(v.cl100k) }])),
  }
}

// Which global-state approach the agent picked for the shop app (first match wins).
const STORES = [
  ['Redux Toolkit', /@reduxjs\/toolkit/],
  ['Redux', /from ['"](react-)?redux['"]/],
  ['Zustand', /from ['"]zustand/],
  ['Jotai', /from ['"]jotai/],
  ['Pinia', /from ['"]pinia['"]/],
  ['Vuex', /from ['"]vuex['"]/],
  ['svelte/store', /from ['"]svelte\/store['"]/],
  ['Svelte runes ($state)', /\$state\(/],
  ['Context + useReducer', /useReducer\(/],
  ['Vue reactive()', /\breactive\(/],
  ['React Context', /createContext\(/],
]

function detectStore(texts) {
  const all = texts.join('\n')
  return STORES.find(([, re]) => re.test(all))?.[0] ?? 'other'
}

function shopSummary(rs) {
  const stores = {}
  for (const r of rs) stores[r.store] = (stores[r.store] ?? 0) + 1
  const s = (f) => stats(rs.map(f))
  return { n: rs.length, solved: rs.filter((r) => r.solved).length, works: rs.filter((r) => r.works).length, stores, files: s((r) => r.fileTokens.length), costUsd: s((r) => r.costUsd), output: s((r) => r.usage.output), turns: s((r) => r.turns), durationS: s((r) => r.durationS), codeTokens: s((r) => r.codeTokens), codeTokensCl100k: s((r) => r.codeTokensCl100k) }
}

const kvBrowserTokens = (front) => front?.components?.KvBrowser?.opus?.median

function comboRow(lang, fw, back, front) {
  if (!back?.codeTokens || front === undefined) return null
  return { lang, fw, backendTokens: back.codeTokens.median, frontendTokens: front, totalTokens: back.codeTokens.median + front, backendCostUsd: back.costUsd?.median ?? null }
}

// Full-stack KV feature in one tokenizer: kvhttp backend code + the KvBrowser component.
function combos(cells, frontends) {
  return MAIN_LANGS
    .flatMap((lang) => Object.keys(FRONTENDS).map((fw) => comboRow(lang, fw, cells[`${lang}/kvhttp`], kvBrowserTokens(frontends[fw]))))
    .filter(Boolean)
    .sort((a, b) => a.totalTokens - b.totalTokens)
}

function solutionSources(r) {
  const sol = join(r.dir, 'solution')
  return solutionFiles(sol)
    .filter((f) => isCounted(sol, f))
    .map((path) => ({ path, text: readFileSync(join(sol, path), 'utf8') }))
}

function exportSolution(r) {
  const files = solutionSources(r)
  writeJson(join(OUT, 'solutions', `${r.agent.id}.json`), { id: r.agent.id, files })
}

// Per-language totals over the given runs' tasks (main track, or one specialised track).
function groupSummary(runs, cells) {
  const byLang = Object.groupBy(runs, (r) => r.lang)
  const tasks = [...new Set(runs.map((r) => r.task))]
  return Object.fromEntries(
    Object.keys(LANGS)
      .filter((l) => byLang[l])
      .map((l) => [l, langSummary(tasks.map((t) => cells[`${l}/${t}`]).filter(Boolean), byLang[l])]),
  )
}

// Speed points per benchmark: 100 × fastest/this (throughput: this/fastest), so 100 = fastest.
// perfTotal = geometric mean of the four; speed index perfScore = 100 / perfTotal (×fastest, 1.00 = fastest everywhere).
const PERF = [['wordfreq', 'perfMs', false], ['lru', 'perfMs', false], ['calc', 'perfMs', false], ['kvhttp', 'perfRps', true]]
const geomean = (xs) => Math.exp(sum(xs.map(Math.log)) / xs.length)

function addSpeedScores(langs, cells) {
  const value = (l, [t, k]) => cells[`${l}/${t}`]?.[k]?.median ?? NaN
  const best = PERF.map((p) => {
    const vals = nums(Object.keys(langs).map((l) => value(l, p)))
    return p[2] ? Math.max(...vals) : Math.min(...vals)
  })
  for (const l of Object.keys(langs)) {
    const points = PERF.map((p, i) => 100 * (p[2] ? value(l, p) / best[i] : best[i] / value(l, p)))
    const all = nums(points).length === PERF.length
    langs[l].perfPoints = Object.fromEntries(PERF.map(([t], i) => [t, nums([points[i]])[0] ?? null]))
    langs[l].perfTotal = all ? geomean(points) : null
    langs[l].perfScore = all ? 100 / langs[l].perfTotal : null
  }
}

// One arm's side of a language, over the given tasks: sums of per-task medians (as in langSummary) and
// of per-task min / max cost (the spread between repetitions), runs that work, spend (write + repair) per
// working run, and the raw performance medians of the benchmarked tasks.
function armSide(cells, runs, lang, tasks) {
  const cs = tasks.map((t) => cells[`${lang}/${t}`])
  const rs = runs.filter((r) => r.lang === lang && tasks.includes(r.task))
  const works = rs.filter((r) => r.works).length
  const spent = sum(rs.map((r) => r.costUsd + (r.repairCostUsd ?? 0)))
  const keys = ['costUsd', 'output', 'turns', 'durationS', 'compileErrors', 'stdlibReads', 'codeTokens']
  const perf = Object.fromEntries(PERF.filter(([t]) => tasks.includes(t)).map(([t, k]) => [t, cells[`${lang}/${t}`]?.[k]?.median ?? null]))
  const spread = { costMin: sum(cs.map((c) => c?.costUsd?.min)), costMax: sum(cs.map((c) => c?.costUsd?.max)) }
  return { n: rs.length, works, firstTry: rs.filter((r) => r.firstCheckPass).length, costPerWorkingUsd: works ? spent / works : null, ...Object.fromEntries(keys.map((k) => [k, med(cs, k)])), ...spread, perf }
}

// How much faster the arm's code is than the baseline's: geometric mean over the benchmarked tasks of
// base time ÷ arm time (throughput: arm ÷ base), so 1.10 = 10% faster with the treatment. Raw medians,
// because each arm's speed index is relative to its own fastest language.
function speedChange(base, arm) {
  const ratios = PERF.map(([t, , higher]) => (higher ? arm.perf[t] / base.perf[t] : base.perf[t] / arm.perf[t])).filter((x) => Number.isFinite(x) && x > 0)
  return ratios.length ? geomean(ratios) : null
}

// Runs until writing the skill has paid for itself: authoring cost ÷ median saving per run. null = no saving.
function breakEven(authorUsd, { base, arm }, nTasks) {
  const saving = (base.costUsd - arm.costUsd) / nTasks
  return Number.isFinite(authorUsd) && saving > 0 ? authorUsd / saving : null
}

// Per-run medians over runs paired by case (language, task, repetition): where the arm's cost comes from.
function pairedEffect(baseRuns, runs) {
  const byId = new Map(baseRuns.map((r) => [r.id, r]))
  const pairs = runs.filter((r) => byId.has(r.id)).map((r) => [byId.get(r.id), r])
  const median = (xs) => stats(xs)?.median ?? null
  const metric = (f) => ({ base: median(pairs.map(([b]) => f(b))), arm: median(pairs.map(([, a]) => f(a))) })
  // The arm's extra spend split by token kind at Claude Code's prices (sums over the pairs, so they add up).
  const extra = Object.fromEntries(Object.entries(PRICE).map(([k, usd]) => [k, (usd / 1e6) * sum(pairs.map(([b, a]) => a.usage[k] - b.usage[k]))]))
  const total = sum(Object.values(extra))
  const costShare = Object.fromEntries(Object.entries(extra).map(([k, v]) => [k, v / total]))
  return { pairs: pairs.length, costUsd: metric((r) => r.costUsd), turns: metric((r) => r.turns), output: metric((r) => r.usage.output), cacheWrite: metric((r) => r.usage.cacheWrite), cacheRead: metric((r) => r.usage.cacheRead), extraUsd: extra, costShare, code: codeEffect(pairs, metric), durationS: metric((r) => r.durationS), fasterRuns: pairs.filter(([b, a]) => a.durationS < b.durationS).length }
}

// Did the code itself change? Over the same pairs: hidden tests passed in round 3, examples passed on the
// first check, runs that left test files behind, compiler errors met, code size and file count.
const TEST_FILE_RE = /(^|\/)(tests?|spec|__tests__)\/|_test\.|\.test\.|(^|\/)test_|Tests?\.|Tests?\//
const hasTests = (r) => (r.fileTokens ?? []).some((f) => TEST_FILE_RE.test(f.path))

function codeEffect(pairs, metric) {
  const both = (f) => ({ base: sum(pairs.map(([b]) => f(b))), arm: sum(pairs.map(([, a]) => f(a))) })
  return {
    solved: both((r) => Number(Boolean(r.solved))),
    firstTry: both((r) => Number(Boolean(r.firstCheckPass))),
    withTests: both((r) => Number(hasTests(r))),
    compileErrors: both((r) => r.compileErrors ?? 0),
    codeTokens: metric((r) => r.codeTokens),
    files: metric((r) => r.fileTokens?.length),
  }
}

// Does the arm's overhead shrink on longer work? Per case (language/task): the baseline's median turns
// against the arm's cost change, as a rank correlation and in bins of baseline turns.
const TURN_BINS = [[0, 5], [5, 8], [8, 12], [12, Infinity]]

function lengthEffect(baseCells, cells) {
  const rows = Object.keys(cells).filter((k) => baseCells[k]?.turns && cells[k]?.costUsd).map((k) => ({ turns: baseCells[k].turns.median, d: cells[k].costUsd.median / baseCells[k].costUsd.median - 1 }))
  const bins = TURN_BINS.map(([lo, hi]) => {
    const ds = rows.filter((r) => r.turns >= lo && r.turns < hi).map((r) => r.d)
    return { lo, hi: Number.isFinite(hi) ? hi : null, n: ds.length, median: stats(ds)?.median ?? null }
  })
  return { cases: rows.length, rho: spearman(rows.map((r) => r.turns), rows.map((r) => r.d)), bins }
}

// This arm vs the published run, per language over the tasks both ran, plus what the skill cost to write.
// How much faster the run's code is than a twin, from paired timings: geometric mean over the tasks of
// the per-task median ratio (time: twin ÷ own; throughput: own ÷ twin). null without paired data.
function pairedSpeed(rs, role) {
  const byTask = Object.groupBy(rs.filter((r) => Number.isFinite(r.twinPerf?.[role]) && Number.isFinite(r.perfMs ?? r.perfRps)), (r) => r.task)
  const ratios = Object.entries(byTask).map(([t, xs]) => {
    const [own, twin] = [stats(xs.map((r) => r.perfMs ?? r.perfRps)).median, stats(xs.map((r) => r.twinPerf[role])).median]
    return t === 'kvhttp' ? own / twin : twin / own
  })
  return ratios.length ? geomean(ratios) : null
}

// Port arm: what migrating cost per 1,000 lines of the source program (write + repair, so a run that
// needed repair is not cheaper than one that did not), and how much faster the port runs than the source.
function portFields(rs, base) {
  const lines = new Map(base.runs.filter((r) => r.lang === PORT_FROM).map((r) => [`${r.task}/${r.rep}`, r.codeLines]))
  const perK = rs.filter((r) => r.works && lines.get(`${r.task}/${r.rep}`)).map((r) => (r.costToGreenUsd / lines.get(`${r.task}/${r.rep}`)) * 1e3)
  return { from: PORT_FROM, costPer1kSourceLines: stats(perK), speedVsSource: pairedSpeed(rs, 'source') }
}

// Swarm arm: how much sooner the team finished than one agent (median solo wall-clock ÷ median team
// wall-clock, both on the harness's clock), the disk its three worktrees held, and the files a trial merge
// of the workers' branches left conflicted (merge.json, measured by the harness).
// Where the team's wall-clock went (medians): the lead, the slowest of the parallel workers, the integrator.
function phaseTimes(rs) {
  const phases = rs.map((r) => r.swarm?.phases ?? [])
  const at = (ps, name) => (ps.find((p) => p.name === name)?.ms ?? 0) / 1000
  const middle = (ps) => ps.filter((p) => p.name !== 'lead' && p.name !== 'integrate').map((p) => p.ms / 1000)
  return {
    leadS: stats(phases.map((ps) => at(ps, 'lead')))?.median,
    slowestWorkerS: stats(phases.map((ps) => Math.max(...middle(ps))))?.median,
    integrateS: stats(phases.map((ps) => at(ps, 'integrate')))?.median,
  }
}

function swarmFields(rs, soloRuns) {
  const wall = (xs) => stats(xs.map((r) => r.wallS))?.median
  return {
    swarm: {
      ...phaseTimes(rs),
      soloWallS: wall(soloRuns),
      teamWallS: wall(rs),
      wallSpeedup: wall(soloRuns) / wall(rs),
      // Peak disk while working (the dev-loop study samples it; earlier runs have none).
      soloPeakBytes: stats(soloRuns.map((r) => r.diskPeakBytes))?.median ?? null,
      teamPeakBytes: stats(rs.map((r) => r.diskPeakBytes))?.median ?? null,
      soloCachePeakBytes: stats(soloRuns.map((r) => r.cachePeakBytes))?.median ?? null,
      teamCachePeakBytes: stats(rs.map((r) => r.cachePeakBytes))?.median ?? null,
      agentS: stats(rs.map((r) => r.swarm?.agentS)),
      worktreeBytes: stats(rs.map((r) => r.swarm?.worktreeBytes)),
      conflictedFiles: sum(rs.map((r) => r.swarm?.conflictedFiles)),
    },
  }
}

// Skills arm: what the skill cost to write, how often it was used, and runs until it pays for itself.
function skillFields(lang, rs, sides, nTasks, beyondNoise, skills) {
  const skill = { costUsd: skills[lang]?.costUsd ?? null, bodyBytes: skills[lang]?.bodyBytes ?? null, usedRate: rs.filter((r) => r.tools?.Skill).length / rs.length }
  // Break-even only for a saving outside the noise: a within-noise "saving" is no saving.
  return { skill, breakEvenRuns: beyondNoise ? breakEven(skill.costUsd, sides, nTasks) : null }
}

// Per language; the swarm arm has two tasks (suite, notes), compared one at a time as "lang/task".
function vsBase(cells, runs) {
  const base = readJson(join(BASE_OUT, 'results.json'))
  const skills = opt(join(SKILLS, 'meta.json')) ?? {}
  const byKey = Object.groupBy(runs, (r) => (ARM === 'swarm' ? `${r.lang}/${r.task}` : r.lang))
  return Object.fromEntries(
    Object.entries(byKey).map(([key, rs]) => {
      const lang = rs[0].lang
      const tasks = [...new Set(rs.map((r) => r.task))].filter((t) => base.summary.cells[`${lang}/${t}`]).sort()
      const sides = { base: armSide(base.summary.cells, base.runs, lang, tasks), arm: armSide(cells, runs, lang, tasks) }
      // A cost change counts only outside the baseline's own spread between repetitions.
      const beyondNoise = sides.arm.costUsd < sides.base.costMin || sides.arm.costUsd > sides.base.costMax
      // Speed vs the same case written from scratch: paired timings when present, else both arms' medians.
      const speed = pairedSpeed(rs, 'scratch') ?? speedChange(sides.base, sides.arm)
      const extra = { skills: () => skillFields(lang, rs, sides, tasks.length, beyondNoise, skills), swarm: () => swarmFields(rs, base.runs.filter((r) => r.lang === lang && tasks.includes(r.task))) }[ARM]?.() ?? { port: portFields(rs, base) }
      return [key, { tasks, ...sides, beyondNoise, speedChange: speed, ...extra }]
    }),
  )
}

// What the whole project spent at list price: every agent run of every arm (write + repair, a swarm team's
// phases included) plus writing the skills. Read straight from runs*/ so it counts arms not aggregated yet.
function projectSpend() {
  const byArm = {}
  let runs = 0
  for (const root of readdirSync(ROOT).filter((n) => n === 'runs' || n.startsWith('runs-'))) {
    const arm = { runs: 'baseline', 'runs-skills': 'skills', 'runs-swarm': 'swarm teams' }[root] ?? 'migration'
    for (const f of readdirSync(join(ROOT, root), { recursive: true }).filter((p) => /(^|\/)(agent|repair)\.json$/.test(p) && !p.includes('repair/'))) {
      if (f.endsWith('agent.json')) runs++
      byArm[arm] = (byArm[arm] ?? 0) + (readJson(join(ROOT, root, f)).costUsd ?? 0)
    }
  }
  byArm['skill writing'] = sum(Object.values(opt(join(SKILLS, 'meta.json')) ?? {}).map((s) => s.costUsd))
  return { runs, usd: sum(Object.values(byArm)), byArm }
}

function build() {
  const raw = collect()
  const runs = raw.map((r) => {
    const sources = solutionSources(r)
    const shop = r.agent.task === 'shop' && { store: detectStore(sources.map((f) => f.text)) }
    return { ...publicRun(r), deps: detectDeps(sources), ...shop }
  })
  const by = (f) => Object.groupBy(runs, f)
  const cellRuns = by((r) => `${r.lang}/${r.task}`)
  const cells = Object.fromEntries(Object.entries(cellRuns).map(([k, rs]) => [k, cellSummary(rs)]))
  const langs = groupSummary(runs.filter((r) => !TASKS[r.task].frontend && !TASKS[r.task].track && !TASKS[r.task].swarm), cells)
  addSpeedScores(langs, cells)
  const tracks = Object.fromEntries(
    Object.entries(TRACKS).map(([id, t]) => [id, { ...t, langs: groupSummary(runs.filter((r) => TASKS[r.task].track === id), cells) }]),
  )
  const frontRuns = Object.groupBy(runs.filter((r) => r.task === 'ui'), (r) => r.lang)
  const frontends = Object.fromEntries(Object.entries(frontRuns).map(([k, rs]) => [k, frontendSummary(rs)]))
  const shopRuns = Object.groupBy(runs.filter((r) => r.task === 'shop'), (r) => r.lang)
  const shop = Object.fromEntries(Object.entries(shopRuns).map(([k, rs]) => [k, shopSummary(rs)]))
  rmSync(join(OUT, 'solutions'), { recursive: true, force: true })
  raw.forEach(exportSolution)
  const toolchains = opt(join(RUNS, 'toolchains.json'))
  // The arms whose data the page can load next to this run (runs-<arm>/ directories).
  const arms = readdirSync(ROOT).filter((n) => n.startsWith('runs-') && existsSync(join(BASE_OUT, n.slice(5), 'results.json'))).map((n) => n.slice(5))
  const spend = ARM === 'base' ? projectSpend() : undefined
  const meta = { generatedAt: new Date().toISOString(), arm: ARM, arms, spend, model: MODEL, effort: EFFORT, toolchains, langs: LANGS, frontends: FRONTENDS, tasks: TASKS, external: EXTERNAL }
  const baseData = ARM === 'base' ? null : readJson(join(BASE_OUT, 'results.json'))
  const compare = baseData ? { vsBase: vsBase(cells, runs), effect: pairedEffect(baseData.runs, runs), length: lengthEffect(baseData.summary.cells, cells) } : {}
  // The swarm arm's two tasks are compared separately.
  if (ARM === 'swarm') compare.effectByTask = Object.fromEntries([...new Set(runs.map((r) => r.task))].map((t) => [t, pairedEffect(baseData.runs.filter((r) => r.task === t), runs.filter((r) => r.task === t))]))
  // The two rankings against each other: cost to write vs speed of the code (main languages).
  const ranked = Object.keys(langs).filter((l) => Number.isFinite(langs[l].perfTotal))
  // What fills Rust's target/ after a debug, a release and a test build (bench/devloop.mjs), medians.
  const parts = raw.map((r) => r.devloop?.parts).filter(Boolean)
  const part = (p, k) => stats(parts.map((x) => x[p][k]))?.median ?? null
  const rustTarget = parts.length ? { debug: part('debug', 'total'), debugDeps: part('debug', 'deps'), debugIncremental: part('debug', 'incremental'), release: part('release', 'total') } : null
  // Disk over an edit-rebuild loop (bench/growth.mjs), one series per language.
  const growth = Object.fromEntries(raw.filter((r) => r.growth).map((r) => [r.agent.lang, r.growth]))
  const costSpeedRho = spearman(ranked.map((l) => langs[l].costUsd), ranked.map((l) => langs[l].perfTotal))
  writeJson(join(OUT, 'results.json'), { meta, summary: { langs, tracks, cells, frontends, shop, combos: combos(cells, frontends), costSpeedRho, growth, rustTarget, ...compare }, runs })
  console.log(`${runs.length} runs → public/data/results.json`)
}

function runProblems(r) {
  const out = []
  if (!existsSync(join(OUT, 'solutions', `${r.id}.json`))) out.push(`${r.id}: solution file missing`)
  if (r.solved === null) out.push(`${r.id}: not verified`)
  if (r.codeTokens === null) out.push(`${r.id}: tokens not counted`)
  return out
}

// An arm is comparable only if it ran the baseline's model(s) and has its comparison.
function armProblems(d) {
  const models = new Set(readJson(join(BASE_OUT, 'results.json')).runs.flatMap((r) => r.models ?? []))
  const out = d.runs.filter((r) => (r.models ?? []).some((m) => !models.has(m))).map((r) => `${r.id}: model ${r.models} not in the baseline`)
  if (!d.summary.vsBase) out.push(`arm ${ARM}: no comparison with the baseline`)
  return out
}

function check() {
  const file = join(OUT, 'results.json')
  if (!existsSync(file)) throw new Error(`${file} missing: run npm run aggregate`)
  const d = readJson(file)
  const problems = d.runs.flatMap(runProblems)
  if (!d.runs.length) problems.push('no runs')
  // A ranked task's runs must reach the language summary (the swarm arm has only the unranked suite task).
  const ranked = d.runs.some((r) => !TASKS[r.task].frontend && !TASKS[r.task].track && !TASKS[r.task].swarm)
  if (ranked && !Object.keys(d.summary.langs).length) problems.push('no language summary')
  if (ARM !== 'base') problems.push(...armProblems(d))
  if (problems.length) {
    console.error(problems.join('\n'))
    process.exit(1)
  }
  console.log(`results.json ok: ${d.runs.length} runs, ${Object.keys(d.summary.langs).length} languages`)
}

if (process.argv.includes('--check')) check()
else build()
