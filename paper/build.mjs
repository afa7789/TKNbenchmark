// Generates paper/data.tex (tables, plots, macros) from public/data/results.json,
// so every number in the paper comes from the benchmark data. Then: tectonic paper/paper.tex
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT, TASKS } from '../bench/config.mjs'

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

function pearson(xs, ys) {
  const mean = (a) => a.reduce((s, x) => s + x, 0) / a.length
  const [mx, my] = [mean(xs), mean(ys)]
  const cov = xs.reduce((s, x, i) => s + (x - mx) * (ys[i] - my), 0)
  const sd = (a, m) => Math.sqrt(a.reduce((s, x) => s + (x - m) ** 2, 0))
  return cov / (sd(xs, mx) * sd(ys, my))
}

const ranks = (xs) => {
  const order = xs.map((x, i) => [x, i]).sort((a, b) => a[0] - b[0])
  const r = []
  order.forEach(([, i], pos) => (r[i] = pos))
  return r
}
const spearman = (xs, ys) => pearson(ranks(xs), ranks(ys))

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
  set('CorrCostSpeed', nf(2)(spearman(keys.map((k) => L[k].costUsd), keys.map((k) => L[k].perfTotal))))
  set('FastestLang', tex(label(bySpeed[0])))
  set('KvPointsMin', int(Math.min(...keys.map((k) => L[k].perfPoints.kvhttp))))
  set('CorrCodeCostNoAsm', nf(2)(pearson(noAsm.map((k) => L[k].codeTokens), noAsm.map((k) => L[k].costUsd))))
  tsJsMacros(set)
  trackMacros(set)
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
].join('\n\n')
writeFileSync(join(ROOT, 'paper', 'data.tex'), out + '\n')
console.log('paper/data.tex written')
