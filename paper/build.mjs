// Generates paper/data.tex (tables, plots, macros) from public/data/results.json,
// so every number in the paper comes from the benchmark data. Then: tectonic paper/paper.tex
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT, TASKS } from '../bench/config.mjs'
import { pearson, spearman } from '../bench/lib.mjs'

const d = JSON.parse(readFileSync(join(ROOT, 'public', 'data', 'results.json'), 'utf8'))
const L = d.summary.langs
const C = d.summary.cells
const label = (k) => (d.meta.langs[k] ?? d.meta.frontends[k]).label
const tex = (s) => String(s).replace(/([#%&_$])/g, '\\$1')

const loc = {
    decimal: '.',
    comma: 'use period',
    lead: 'Language & Solved & 1st try & US\\$ & Output & Turns & Min & Code & Errors & Stdlib',
    costAxis: 'US\\$ for 4 tasks (sum of medians)',
    codeAxis: 'final code tokens (Opus 5.5, thousands)',
    kv: 'Language & Dependencies (most common) & MB & Build s & req/s',
    perf: 'Language & wordfreq ms & lru ms & calc ms & lru RSS MB',
    speed: '\\# & Language & wordfreq & lru & calc & kvhttp & Score & $\\times$fastest',
    front: [' & Article & Ours & Ours & ui & shop & Store in shop', " & cl100k & cl100k & Opus & tokens & tokens & (agent's choice)"],
}

const nf = (digits) => (v) => (typeof v === 'number' && Number.isFinite(v) ? v.toFixed(digits).replace('.', loc.decimal) : '--')
const int = (v) => (typeof v === 'number' ? String(Math.round(v)).replace(/\B(?=(\d{3})+(?!\d))/g, '\\,') : '--')
const usd = nf(2)
const mb = (v) => nf(v >= 10e6 ? 0 : 1)(v / 1e6)
const byCost = Object.keys(L).sort((a, b) => L[a].costUsd - L[b].costUsd)
const macroName = (k) => k.replace(/[^a-z]/gi, '').replace(/^./, (c) => c.toUpperCase())

function leaderboard() {
  const rows = byCost.map((k) => {
    const s = L[k]
    return `${tex(label(k))} & ${s.solved}/${s.n} & ${nf(0)(s.firstTryRate * 100)}\\% & ${usd(s.costUsd)} & ${int(s.output)} & ${int(s.turns)} & ${nf(1)(s.durationS / 60)} & ${int(s.codeTokens)} & ${nf(1)(s.compileErrors)} & ${nf(0)(s.stdlibReads)} \\\\`
  })
  return `\\newcommand{\\LeaderboardTable}{%
\\begin{tabular}{@{}lrrrrrrrrr@{}}
\\toprule
${loc.lead} \\\\
\\midrule
${rows.join('\n')}
\\bottomrule
\\end{tabular}}`
}

function barPlot(name, key, xlabel, scale = 1) {
  const keys = [...byCost].sort((a, b) => L[b][key] - L[a][key])
  const coords = keys.map((k) => `(${(L[k][key] * scale).toFixed(3)},${macroName(k)})`).join(' ')
  return `\\newcommand{\\${name}}{%
\\begin{tikzpicture}
\\begin{axis}[xbar, width=0.95\\columnwidth, height=${0.42 * keys.length + 1.2}cm, bar width=5pt, xmin=0,
  symbolic y coords={${keys.map(macroName).join(',')}}, ytick=data, yticklabels={${keys.map((k) => tex(label(k))).join(',')}},
  xlabel={${xlabel}}, nodes near coords, nodes near coords style={font=\\tiny}, every node near coord/.append style={/pgf/number format/.cd, fixed, precision=2, ${loc.comma}},
  tick label style={font=\\footnotesize}, label style={font=\\footnotesize}, axis x line*=bottom, axis y line*=left, enlarge y limits=0.06, xmajorgrids, major grid style={gray!20}]
\\addplot[fill=black, draw=none] coordinates {${coords}};
\\end{axis}
\\end{tikzpicture}}`
}

function kvTable() {
  const keys = Object.keys(L).sort((a, b) => (C[`${b}/kvhttp`]?.footprintBytes?.median ?? 0) - (C[`${a}/kvhttp`]?.footprintBytes?.median ?? 0))
  const rows = keys.map((k) => {
    const c = C[`${k}/kvhttp`]
    const deps = Object.keys(c.deps).sort((a, b) => c.deps[b] - c.deps[a])[0] || 'stdlib'
    return `${tex(label(k))} & ${tex(deps)} & ${mb(c.footprintBytes?.median)} & ${nf(1)(c.buildSecs?.median)} & ${int(c.perfRps?.median)} \\\\`
  })
  return `\\newcommand{\\KvTable}{%
\\begin{tabular}{@{}l>{\\raggedright\\arraybackslash}p{3.6cm}rrr@{}}
\\toprule
${loc.kv} \\\\
\\midrule
${rows.join('\n')}
\\bottomrule
\\end{tabular}}`
}

function perfTable() {
  const keys = Object.keys(L).sort((a, b) => (C[`${a}/calc`]?.perfMs?.median ?? 1e9) - (C[`${b}/calc`]?.perfMs?.median ?? 1e9))
  const ms = (k, t) => int(C[`${k}/${t}`]?.perfMs?.median)
  const rows = keys.map((k) => `${tex(label(k))} & ${ms(k, 'wordfreq')} & ${ms(k, 'lru')} & ${ms(k, 'calc')} & ${mb(C[`${k}/lru`]?.perfRssBytes?.median)} \\\\`)
  return `\\newcommand{\\PerfTable}{%
\\begin{tabular}{@{}lrrrr@{}}
\\toprule
${loc.perf} \\\\
\\midrule
${rows.join('\n')}
\\bottomrule
\\end{tabular}}`
}

// Performance ranking: points per task (100 = fastest), score = geometric mean, best first.
const bySpeed = Object.keys(L).sort((a, b) => (L[b].perfTotal ?? -1) - (L[a].perfTotal ?? -1))

function speedTable() {
  const rows = bySpeed.map((k, i) => {
    const p = L[k].perfPoints ?? {}
    return `${i + 1} & ${tex(label(k))} & ${int(p.wordfreq)} & ${int(p.lru)} & ${int(p.calc)} & ${int(p.kvhttp)} & \\textbf{${nf(1)(L[k].perfTotal)}} & ${nf(2)(L[k].perfScore)} \\\\`
  })
  return `\\newcommand{\\SpeedTable}{%
\\begin{tabular}{@{}rlrrrrrr@{}}
\\toprule
${loc.speed} \\\\
\\midrule
${rows.join('\n')}
\\bottomrule
\\end{tabular}}`
}

function frontTable() {
  const F = d.summary.frontends
  const S = d.summary.shop
  const base = (t) => F.svelte[t].median
  const rows = Object.keys(F).map((k) => {
    const art = d.meta.external.multipliers[label(k)]
    return `${tex(label(k))} & ${nf(3)(art)} & ${nf(3)(F[k].codeTokensCl100k.median / base('codeTokensCl100k'))} & ${nf(3)(F[k].codeTokens.median / base('codeTokens'))} & ${int(F[k].codeTokens.median)} & ${int(S[k]?.codeTokens?.median)} & ${tex(Object.keys(S[k]?.stores ?? {}).join(', '))} \\\\`
  })
  return `\\newcommand{\\FrontTable}{%
\\begin{tabular}{@{}lrrrrr>{\\raggedright\\arraybackslash}p{3cm}@{}}
\\toprule
${loc.front[0]} \\\\
${loc.front[1]} \\\\
\\midrule
${rows.join('\n')}
\\bottomrule
\\end{tabular}}`
}

// One table for the specialised tracks, grouped by track, cheapest language first.
function trackRows(t) {
  return Object.entries(t.langs)
    .sort((a, b) => a[1].costUsd - b[1].costUsd)
    .map(([k, s], i) => `${i ? '' : tex(t.title)} & ${tex(label(k))} & ${s.solved}/${s.n} & ${s.works}/${s.n} & ${nf(0)(s.firstTryRate * 100)}\\% & ${usd(s.costUsd)} & ${int(s.output)} & ${int(s.codeTokens)} & ${int(s.turns)} \\\\`)
}

function trackTable() {
  const groups = Object.values(d.summary.tracks ?? {}).filter((t) => Object.keys(t.langs).length)
  return `\\newcommand{\\TrackTable}{%
\\begin{tabular}{@{}llrrrrrrr@{}}
\\toprule
Track & Language & Solved & Repaired & 1st try & US\\$ & Output & Code & Turns \\\\
\\midrule
${groups.map((t) => trackRows(t).join('\n')).join('\n\\midrule\n')}
\\bottomrule
\\end{tabular}}`
}

function trackMacros(set) {
  const T = d.summary.tracks ?? {}
  const runs = d.runs.filter((r) => TASKS[r.task]?.track)
  set('NTrackRuns', runs.length)
  set('NTrackLangs', Object.values(T).reduce((a, t) => a + Object.keys(t.langs).length, 0))
  set('NTrackFailed', runs.filter((r) => r.solved === false).length)
  set('NTrackFixed', runs.filter((r) => r.fixed).length)
  for (const [id, t] of Object.entries(T)) {
    for (const [k, s] of Object.entries(t.langs)) set(`Trk${macroName(id)}${macroName(k)}`, usd(s.costUsd))
  }
}

const STDLIB_TASKS = ['wordfreq', 'lru', 'calc']
const medianOf = (xs) => {
  const v = xs.filter((x) => typeof x === 'number').sort((a, b) => a - b)
  return v.length ? v[Math.floor(v.length / 2)] : null
}
const stdlibMedian = (k, key) => medianOf(STDLIB_TASKS.map((t) => C[`${k}/${t}`]?.[key]?.median))


function langMacros(set, k) {
  const m = macroName(k)
  set(`Cost${m}`, usd(L[k].costUsd))
  set(`Out${m}`, int(L[k].output))
  set(`Code${m}`, int(L[k].codeTokens))
  set(`First${m}`, nf(0)(L[k].firstTryRate * 100))
  set(`Std${m}`, nf(0)(L[k].stdlibReads))
  set(`Err${m}`, nf(0)(L[k].compileErrors))
  set(`Min${m}`, nf(1)(L[k].durationS / 60))
  set(`KvDisk${m}`, mb(C[`${k}/kvhttp`]?.footprintBytes?.median))
  set(`KvBuild${m}`, nf(1)(C[`${k}/kvhttp`]?.buildSecs?.median))
  set(`StdBuild${m}`, nf(1)(stdlibMedian(k, 'buildSecs')))
  set(`KvProj${m}`, mb(C[`${k}/kvhttp`]?.projectBytes?.median))
  set(`KvWt${m}`, mb(C[`${k}/kvhttp`]?.worktrees4Bytes?.median))
  set(`StdDisk${m}`, mb(stdlibMedian(k, 'footprintBytes')))
  set(`Speed${m}`, nf(2)(L[k].perfScore))
}

// The series' headline comparison: TypeScript vs JavaScript.
function tsJsMacros(set) {
  if (!L.ts || !L.js) return
  set('TsJsCode', nf(2)(L.ts.codeTokens / L.js.codeTokens))
  set('TsJsCodeClk', nf(2)(L.ts.codeTokensCl100k / L.js.codeTokensCl100k))
  set('TsJsCost', nf(2)(L.ts.costUsd / L.js.costUsd))
}

// ---------- skills arm (public/data/skills/results.json, written by TKN_ARM=skills npm run aggregate) ----------
const ARM_FILE = join(ROOT, 'public', 'data', 'skills', 'results.json')
const ARM_JSON = existsSync(ARM_FILE) ? JSON.parse(readFileSync(ARM_FILE, 'utf8')) : { summary: {}, runs: [] }
const ARM_DATA = ARM_JSON.summary
const V = ARM_DATA.vsBase ?? {}
const change = (a, b) => (a ? b / a - 1 : NaN)
const pct = (v) => (Number.isFinite(v) ? `${v > 0 ? '+' : ''}${nf(0)(v * 100)}\\%` : '--')
const dCost = (k) => change(V[k].base.costUsd, V[k].arm.costUsd)
const skillKeys = Object.keys(V).sort((a, b) => dCost(a) - dCost(b))
const mainSkillKeys = skillKeys.filter((k) => L[k])

function skillTable() {
  const rows = skillKeys.map((k) => {
    const v = V[k]
    const pays = Number.isFinite(v.breakEvenRuns) ? nf(1)(v.breakEvenRuns) : 'no saving'
    return `${tex(label(k))} & ${v.base.works}/${v.base.n}\\,$\\to$\\,${v.arm.works}/${v.arm.n} & ${usd(v.base.costUsd)}\\,$\\to$\\,${usd(v.arm.costUsd)} & ${pct(dCost(k))}${v.beyondNoise ? '' : '$^{\\sim}$'} & ${pct(change(v.base.output, v.arm.output))} & ${nf(1)(v.base.compileErrors)}\\,$\\to$\\,${nf(1)(v.arm.compileErrors)} & ${nf(0)(v.skill.usedRate * 100)}\\% & ${usd(v.skill.costUsd)} & ${pays} \\\\`
  })
  return `\\newcommand{\\SkillTable}{%
\\begin{tabular}{@{}lrrrrrrrr@{}}
\\toprule
Language & Works & US\\$ & $\\Delta$US\\$ & $\\Delta$Output & Errors & Used & Skill US\\$ & Pays off \\\\
\\midrule
${rows.join('\n')}
\\bottomrule
\\end{tabular}}`
}

// Slope chart: place in the cost ranking without (left) and with (right) the skill, main languages.
function skillSlope() {
  const rank = (side) => Object.fromEntries([...mainSkillKeys].sort((a, b) => V[a][side].costUsd - V[b][side].costUsd).map((k, i) => [k, i]))
  const [rb, ra] = [rank('base'), rank('arm')]
  const y = (i) => nf(2)(-0.42 * i)
  const lines = mainSkillKeys.map((k) => {
    const style = Math.abs(rb[k] - ra[k]) >= 3 ? 'black, line width=0.9pt' : 'black!35, line width=0.6pt'
    return `\\draw[${style}] (0,${y(rb[k])}) -- (4,${y(ra[k])});
\\node[anchor=east, font=\\scriptsize] at (-0.1,${y(rb[k])}) {${rb[k] + 1}. ${tex(label(k))}};
\\node[anchor=west, font=\\scriptsize] at (4.1,${y(ra[k])}) {${ra[k] + 1}. ${tex(label(k))}};`
  })
  return `\\newcommand{\\SkillSlope}{%
\\begin{tikzpicture}
\\node[anchor=east, font=\\footnotesize\\bfseries] at (-0.1,0.5) {Without skill};
\\node[anchor=west, font=\\footnotesize\\bfseries] at (4.1,0.5) {With skill};
${lines.join('\n')}
\\end{tikzpicture}}`
}

function skillMacros(set) {
  const n = skillKeys.length
  set('NSkillLangs', n)
  set('NSkillCheaper', skillKeys.filter((k) => dCost(k) < 0 && V[k].beyondNoise).length)
  set('NSkillCostlier', skillKeys.filter((k) => dCost(k) > 0 && V[k].beyondNoise).length)
  set('NSkillWorksUp', skillKeys.filter((k) => V[k].arm.works > V[k].base.works).length)
  set('NSkillWorksDown', skillKeys.filter((k) => V[k].arm.works < V[k].base.works).length)
  const mid = mainSkillKeys.map(dCost).sort((a, b) => a - b)[mainSkillKeys.length >> 1]
  set('SkillMedianChange', pct(mid))
  set('SkillAuthorCost', usd(skillKeys.reduce((a, k) => a + (V[k].skill.costUsd ?? 0), 0)))
  const sumOf = (side, key) => skillKeys.reduce((a, k) => a + V[k][side][key], 0)
  set('NSkillFailed', ARM_JSON.runs.filter((r) => r.solved === false).length)
  set('NSkillFixed', ARM_JSON.runs.filter((r) => r.fixed).length)
  set('SkillWorksBase', `${sumOf('base', 'works')}/${sumOf('base', 'n')}`)
  set('SkillWorksArm', `${sumOf('arm', 'works')}/${sumOf('arm', 'n')}`)
  // Paired per-run medians: where the arm's extra cost comes from.
  const none = { base: NaN, arm: NaN }
  const e = ARM_DATA.effect ?? { pairs: 0, costUsd: none, turns: none, cacheWrite: none, cacheRead: none, output: none }
  const effPct = (m) => pct(change(m.base, m.arm))
  set('NSkillPairs', e.pairs)
  const speeds = mainSkillKeys.map((k) => V[k].speedChange).filter(Number.isFinite).sort((a, b) => a - b)
  set('SkillSpeedMedian', nf(2)(speeds[speeds.length >> 1]))
  set('SkillRunCostBase', nf(3)(e.costUsd.base))
  set('SkillRunCostArm', nf(3)(e.costUsd.arm))
  set('SkillRunCostPct', effPct(e.costUsd))
  set('SkillTurnsBase', nf(0)(e.turns.base))
  set('SkillTurnsArm', nf(0)(e.turns.arm))
  set('SkillCacheWritePct', effPct(e.cacheWrite))
  set('SkillCacheReadPct', effPct(e.cacheRead))
  set('SkillOutputPct', effPct(e.output))
  const len = ARM_DATA.length ?? { rho: NaN, bins: [{}, {}, {}, {}] }
  set('SkillLenRho', nf(2)(len.rho))
  set('SkillLenShort', pct(len.bins[0].median))
  set('SkillLenLong', pct(len.bins.at(-1).median))
  set('SkillLenLongN', len.bins.at(-1).n ?? 0)
  const share = e.costShare ?? {}
  set('SkillShareWrite', `${nf(0)(share.cacheWrite * 100)}\\%`)
  set('SkillShareRead', `${nf(0)(share.cacheRead * 100)}\\%`)
  set('SkillShareOutput', `${nf(0)(share.output * 100)}\\%`)
  const z = V.zig ?? { base: {}, arm: {} }
  set('ZigStdBase', nf(0)(z.base.stdlibReads))
  set('ZigStdArm', nf(0)(z.arm.stdlibReads))
  set('ZigOutPct', pct(change(z.base.output, z.arm.output)))
  for (const k of skillKeys) {
    set(`SkillDelta${macroName(k)}`, pct(dCost(k)))
    set(`SkillCost${macroName(k)}`, usd(V[k].arm.costUsd))
  }
}

// ---------- port arms (public/data/port-<src>/results.json): migrating the slowest languages ----------
const PORTS = (d.meta.arms ?? [])
  .filter((a) => a.startsWith('port-'))
  .map((a) => ({ src: a.slice(5), v: JSON.parse(readFileSync(join(ROOT, 'public', 'data', a, 'results.json'), 'utf8')).summary.vsBase }))
const portPairs = PORTS.flatMap(({ src, v }) => Object.keys(v).sort((a, b) => label(a).localeCompare(label(b))).map((t) => ({ src, t, x: v[t] })))
const perK = (p) => p.x.port.costPer1kSourceLines?.median

function portTable() {
  const rows = portPairs.map(({ src, t, x }) => {
    const d = change(x.base.costUsd, x.arm.costUsd)
    return `${tex(label(src))} $\\to$ ${tex(label(t))} & ${x.arm.works}/${x.arm.n} & ${usd(x.base.costUsd)}\\,$\\to$\\,${usd(x.arm.costUsd)} & ${pct(d)}${x.beyondNoise ? '' : '$^{\\sim}$'} & ${usd(perK({ x }))} & ${nf(1)(x.port.speedVsSource)} \\\\`
  })
  return `\\newcommand{\\PortTable}{%
\\begin{tabular}{@{}lrrrrr@{}}
\\toprule
From $\\to$ to & Works & US\\$ scratch $\\to$ port & $\\Delta$US\\$ & US\\$ / 1k lines & $\\times$faster \\\\
\\midrule
${rows.join('\n')}
\\bottomrule
\\end{tabular}}`
}

function portMacros(set) {
  const works = portPairs.reduce((a, p) => a + p.x.arm.works, 0)
  const n = portPairs.reduce((a, p) => a + p.x.arm.n, 0)
  set('NPortPairs', portPairs.length)
  set('PortWorks', `${works}/${n}`)
  const deltas = portPairs.map((p) => change(p.x.base.costUsd, p.x.arm.costUsd)).sort((a, b) => a - b)
  set('PortDeltaMedian', pct(deltas[deltas.length >> 1]))
  set('NPortCheaper', portPairs.filter((p) => p.x.arm.costUsd < p.x.base.costUsd && p.x.beyondNoise).length)
  set('NPortCostlier', portPairs.filter((p) => p.x.arm.costUsd > p.x.base.costUsd && p.x.beyondNoise).length)
  set('PortDeltaMin', pct(deltas[0]))
  set('PortDeltaMax', pct(deltas.at(-1)))
  // Speed gained per target: median over the sources of the port's speed relative to the source.
  for (const [t, ps] of Object.entries(Object.groupBy(portPairs, (p) => p.t))) {
    const xs = ps.map((p) => p.x.port.speedVsSource).sort((a, b) => a - b)
    set(`PortSpeed${macroName(t)}`, nf(1)(xs[xs.length >> 1]))
  }
  const byCost = [...portPairs].filter((p) => Number.isFinite(perK(p))).sort((a, b) => perK(a) - perK(b))
  const name = (p) => `${tex(label(p.src))}$\\to$${tex(label(p.t))}`
  if (byCost.length) {
    set('PortPerKMin', usd(perK(byCost[0])))
    set('PortPerKMinPair', name(byCost[0]))
    set('PortPerKMax', usd(perK(byCost.at(-1))))
    set('PortPerKMaxPair', name(byCost.at(-1)))
  }
  for (const p of portPairs) {
    const m = `${macroName(p.src)}${macroName(p.t)}`
    set(`Port${m}PerK`, usd(perK(p)))
    set(`Port${m}Speed`, nf(1)(p.x.port.speedVsSource))
  }
}

// ---------- swarm arm (public/data/swarm/results.json): a team of agents vs one ----------
const SW = (d.meta.arms ?? []).includes('swarm') ? JSON.parse(readFileSync(join(ROOT, 'public', 'data', 'swarm', 'results.json'), 'utf8')).summary.vsBase : {}
const secs = (s) => nf(0)(s)

function swarmTable() {
  const rows = Object.entries(SW).map(([k, v]) => `${tex(label(k))} & ${v.base.works}/${v.base.n}\\,$\\to$\\,${v.arm.works}/${v.arm.n} & ${usd(v.base.costUsd)}\\,$\\to$\\,${usd(v.arm.costUsd)} & ${secs(v.base.durationS)}\\,$\\to$\\,${secs(v.arm.durationS)} & ${nf(2)(v.swarm.wallSpeedup)} & ${mb(v.swarm.worktreeBytes?.median)} & ${int(v.swarm.conflicts)} \\\\`)
  return `\\newcommand{\\SwarmTable}{%
\\begin{tabular}{@{}lrrrrrr@{}}
\\toprule
Language & Works & US\\$ solo $\\to$ team & s solo $\\to$ team & $\\times$sooner & MB 3 trees & Conflicts \\\\
\\midrule
${rows.join('\n')}
\\bottomrule
\\end{tabular}}`
}

function swarmMacros(set) {
  const vs = Object.values(SW)
  const speed = vs.map((v) => v.swarm.wallSpeedup)
  const dc = vs.map((v) => change(v.base.costUsd, v.arm.costUsd))
  set('NSwarmLangs', vs.length)
  set('NSwarmSooner', vs.filter((v) => v.swarm.wallSpeedup > 1).length)
  set('SwarmSpeedMin', nf(2)(Math.min(...speed)))
  set('SwarmSpeedMax', nf(2)(Math.max(...speed)))
  set('SwarmCostMin', pct(Math.min(...dc)))
  set('SwarmCostMax', pct(Math.max(...dc)))
  set('SwarmConflicts', int(vs.reduce((a, v) => a + v.swarm.conflicts, 0)))
  for (const [k, v] of Object.entries(SW)) set(`SwarmDisk${macroName(k)}`, mb(v.swarm.worktreeBytes?.median))
}

function macros() {
  const out = []
  const set = (name, v) => out.push(`\\newcommand{\\${name}}{${v}}`)
  const runs = d.runs.length
  set('NRuns', runs)
  set('NLangs', Object.keys(L).length)
  set('TotalCost', usd(d.runs.reduce((a, r) => a + (r.costUsd ?? 0), 0)))
  set('NFailedRoundThree', d.runs.filter((r) => r.solved === false).length)
  set('NFixed', d.runs.filter((r) => r.fixed).length)
  for (const k of Object.keys(L)) langMacros(set, k)
  const keys = Object.keys(L)
  set('CorrCodeCost', nf(2)(pearson(keys.map((k) => L[k].codeTokens), keys.map((k) => L[k].costUsd))))
  const noAsm = keys.filter((k) => k !== 'asm')
  set('CorrCodeCostSpearman', nf(2)(spearman(keys.map((k) => L[k].codeTokens), keys.map((k) => L[k].costUsd))))
  set('CorrCostSpeed', nf(2)(d.summary.costSpeedRho))
  set('FastestLang', tex(label(bySpeed[0])))
  set('KvPointsMin', int(Math.min(...keys.map((k) => L[k].perfPoints.kvhttp))))
  set('CorrCodeCostNoAsm', nf(2)(pearson(noAsm.map((k) => L[k].codeTokens), noAsm.map((k) => L[k].costUsd))))
  tsJsMacros(set)
  trackMacros(set)
  skillMacros(set)
  portMacros(set)
  swarmMacros(set)
  set('CorrStdCost', nf(2)(pearson(keys.map((k) => L[k].stdlibReads), keys.map((k) => L[k].costUsd))))
  const dl = C['rust/kvhttp']?.devloopTargetBytes?.median
  set('DevloopRust', mb(dl))
  set('DevloopRustWt', mb(4 * dl + (C['rust/kvhttp']?.cacheBytes?.median ?? 0)))
  set('NDepsLangs', keys.filter((k) => Object.keys(C[`${k}/kvhttp`]?.deps ?? {}).some(Boolean)).length)
  const cheapest = byCost[0]
  set('CheapestLang', tex(label(cheapest)))
  set('CostCheapest', usd(L[cheapest].costUsd))
  set('ShortestLang', tex(label(Object.keys(L).sort((a, b) => L[a].codeTokens - L[b].codeTokens)[0])))
  for (const k of Object.keys(L)) set(`Ratio${macroName(k)}`, nf(1)(L[k].costUsd / L[cheapest].costUsd))
  for (const c of d.summary.combos) set(`Combo${macroName(c.lang)}${macroName(c.fw)}`, int(c.totalTokens))
  return out.join('\n')
}

const out = [
  `% Generated by paper/build.mjs from public/data/results.json (${d.meta.generatedAt}). Do not edit.`,
  macros(),
  leaderboard(),
  barPlot('CostPlot', 'costUsd', loc.costAxis),
  barPlot('CodePlot', 'codeTokens', loc.codeAxis, 0.001),
  kvTable(),
  perfTable(),
  speedTable(),
  frontTable(),
  trackTable(),
  skillTable(),
  skillSlope(),
  portTable(),
  swarmTable(),
].join('\n\n')
writeFileSync(join(ROOT, 'paper', 'data.tex'), out + '\n')
console.log('paper/data.tex written')
