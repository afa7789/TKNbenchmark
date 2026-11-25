// Collects runs/ into public/data/results.json (+ one solutions/<id>.json per run for the code viewer).
// node bench/aggregate.mjs          build the data
// node bench/aggregate.mjs --check  validate the committed data (CI smoke)
import { existsSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT, RUNS, LANGS, FRONTENDS, TASKS, TRACKS, MODEL, EFFORT, MAIN_LANGS, ARM, SKILLS } from './config.mjs'
import { isCounted, readJson, solutionFiles, writeJson } from './lib.mjs'
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
        if (agent) runs.push({ dir, agent, verify: opt(join(dir, 'verify.json')), tokens: opt(join(dir, 'tokens.json')), perf: opt(join(dir, 'perf.json')), repair: opt(join(dir, 'repair.json')), devloop: opt(join(dir, 'devloop.json')) })
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

function publicRun({ agent: a, verify: v, tokens: t, perf: p, repair: rp, devloop: dl }) {
  return {
    ...fields(a, same('id', 'lang', 'task', 'rep', 'finished', 'terminalReason', 'costUsd', 'turns', 'usage', 'tools', 'builds', 'compileErrors', 'stdlibReads', 'checkRuns', 'firstCheckPass')),
    durationS: a.durationMs / 1000,
    apiS: a.apiMs / 1000,
    ...fields(v, same('solved', 'pass', 'total', 'buildOk', 'buildSecs', 'footprintBytes', 'projectBytes', 'cacheBytes', 'binaryBytes')),
    failures: (v?.cases ?? []).filter((c) => !c.ok).map((c) => ({ name: c.name, why: c.why })),
    ...fields(t, { codeTokens: 'opus', codeTokensCl100k: 'cl100k', codeChars: 'chars', codeLines: 'lines' }),
    fileTokens: t?.files ?? [],
    ...fields(p, { perfMs: 'wallMs', perfRps: 'rps', perfRssBytes: 'rssBytes' }),
    ...repairFields(a, v, rp),
    worktrees4Bytes: worktrees(v, 4),
    devloopTargetBytes: dl?.targetBytes ?? null,
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

// One arm's side of a language, over the given tasks: sums of per-task medians (as in langSummary),
// runs that work, and spend (write + repair) per working run.
function armSide(cells, runs, lang, tasks) {
  const cs = tasks.map((t) => cells[`${lang}/${t}`])
  const rs = runs.filter((r) => r.lang === lang && tasks.includes(r.task))
  const works = rs.filter((r) => r.works).length
  const spent = sum(rs.map((r) => r.costUsd + (r.repairCostUsd ?? 0)))
  const keys = ['costUsd', 'output', 'turns', 'durationS', 'compileErrors', 'stdlibReads', 'codeTokens']
  return { n: rs.length, works, firstTry: rs.filter((r) => r.firstCheckPass).length, costPerWorkingUsd: works ? spent / works : null, ...Object.fromEntries(keys.map((k) => [k, med(cs, k)])) }
}

// This arm vs the published run, per language over the tasks both ran, plus what the skill cost to write.
function vsBase(cells, runs, langs) {
  const base = readJson(join(BASE_OUT, 'results.json'))
  const skills = opt(join(SKILLS, 'meta.json')) ?? {}
  const byLang = Object.groupBy(runs, (r) => r.lang)
  return Object.fromEntries(
    Object.entries(byLang).map(([lang, rs]) => {
      const tasks = [...new Set(rs.map((r) => r.task))].filter((t) => base.summary.cells[`${lang}/${t}`]).sort()
      const perfScore = { base: base.summary.langs[lang]?.perfScore ?? null, arm: langs[lang]?.perfScore ?? null }
      const skill = { costUsd: skills[lang]?.costUsd ?? null, bodyBytes: skills[lang]?.bodyBytes ?? null, usedRate: rs.filter((r) => r.tools?.Skill).length / rs.length }
      return [lang, { tasks, base: armSide(base.summary.cells, base.runs, lang, tasks), arm: armSide(cells, runs, lang, tasks), perfScore, skill }]
    }),
  )
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
  const langs = groupSummary(runs.filter((r) => !TASKS[r.task].frontend && !TASKS[r.task].track), cells)
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
  const meta = { generatedAt: new Date().toISOString(), arm: ARM, model: MODEL, effort: EFFORT, toolchains, langs: LANGS, frontends: FRONTENDS, tasks: TASKS, external: EXTERNAL }
  const compare = ARM === 'base' ? {} : { vsBase: vsBase(cells, runs, langs) }
  writeJson(join(OUT, 'results.json'), { meta, summary: { langs, tracks, cells, frontends, shop, combos: combos(cells, frontends), ...compare }, runs })
  console.log(`${runs.length} runs → public/data/results.json`)
}

function runProblems(r) {
  const out = []
  if (!existsSync(join(OUT, 'solutions', `${r.id}.json`))) out.push(`${r.id}: solution file missing`)
  if (r.solved === null) out.push(`${r.id}: not verified`)
  if (r.codeTokens === null) out.push(`${r.id}: tokens not counted`)
  return out
}

function check() {
  const file = join(OUT, 'results.json')
  if (!existsSync(file)) throw new Error(`${file} missing: run npm run aggregate`)
  const d = readJson(file)
  const problems = d.runs.flatMap(runProblems)
  if (!d.runs.length) problems.push('no runs')
  if (!Object.keys(d.summary.langs).length) problems.push('no language summary')
  if (ARM !== 'base' && !d.summary.vsBase) problems.push(`arm ${ARM}: no comparison with the baseline`)
  if (problems.length) {
    console.error(problems.join('\n'))
    process.exit(1)
  }
  console.log(`results.json ok: ${d.runs.length} runs, ${Object.keys(d.summary.langs).length} languages`)
}

if (process.argv.includes('--check')) check()
else build()
