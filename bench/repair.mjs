// Round 4: every run that failed round 3 gets a fresh agent with the failure report, up to 3 attempts.
// Measures tokens, cost and time until it passes. node bench/repair.mjs [--attempts 3] [--jobs 1]
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { RUNS, WORK, TASKS, repairPrompt } from './config.mjs'
import { prepareWorkdir, runAgent } from './agent.mjs'
import { copyFiles, parseArgs, pool, readJson, solutionFiles, writeJson } from './lib.mjs'
import { parseTranscript } from './transcript.mjs'
import { builtDir, verifySolution } from './verify.mjs'
import { verifyFront } from './verify-front.mjs'

const args = parseArgs(process.argv.slice(2), { attempts: '3', jobs: '1' })
const versions = readJson(join(RUNS, 'toolchains.json'))

function report(v) {
  if (!v.buildOk) return `Build failed:\n${v.buildLog || '(no output)'}`
  const failed = v.cases.filter((c) => !c.ok)
  const lines = failed.slice(0, 8).map((c) => `- ${c.name}: ${c.why ?? 'failed'}`)
  return `${v.pass}/${v.total} acceptance checks passed. Failing:\n${lines.join('\n')}${failed.length > 8 ? `\n- …and ${failed.length - 8} more` : ''}`
}

const verifyAny = (sol, meta, id) => (TASKS[meta.task].frontend ? verifyFront(sol, meta.lang, meta.task, id) : verifySolution(sol, meta.task, id, meta.lang))

async function attempt(run, meta, n, sol, last) {
  const id = `${meta.id}-fix${n}`
  const dir = join(WORK, 'repair', id)
  const out = join(run, 'repair', `a${n}`)
  await prepareWorkdir(meta.task, dir, meta.lang)
  copyFiles(sol, dir, solutionFiles(sol))
  rmSync(out, { recursive: true, force: true })
  mkdirSync(out, { recursive: true })
  const transcript = join(out, 'transcript.jsonl')
  await runAgent(dir, repairPrompt(meta.task, meta.lang, versions[meta.lang], report(last)), transcript)
  const metrics = parseTranscript(readFileSync(transcript, 'utf8'))
  // A usage limit or API failure is not a failed repair: leave the run for the next pass.
  if (metrics.terminalReason === 'api_error') return { apiError: metrics.reply }
  copyFiles(dir, join(out, 'solution'), solutionFiles(dir))
  const v = await verifyAny(join(out, 'solution'), meta, id)
  if (v.solved && !TASKS[meta.task].frontend) {
    rmSync(builtDir(meta.id), { recursive: true, force: true })
    renameSync(builtDir(id), builtDir(meta.id))
  }
  const rec = { n, report: report(last), ...metrics, verify: v }
  writeJson(join(out, 'attempt.json'), rec)
  return rec
}

async function repair(run) {
  const meta = readJson(join(run, 'agent.json'))
  let last = readJson(join(run, 'verify.json'))
  let sol = join(run, 'solution')
  const attempts = []
  for (let n = 1; n <= Number(args.attempts) && !last.solved; n++) {
    const a = await attempt(run, meta, n, sol, last)
    if (a.apiError) return console.log(`✖ ${meta.id}: API error, not recorded, rerun later. ${a.apiError}`)
    attempts.push({ n, costUsd: a.costUsd, durationS: a.durationMs / 1000, turns: a.turns, usage: a.usage, compileErrors: a.compileErrors, pass: a.verify.pass, total: a.verify.total, solved: a.verify.solved })
    last = a.verify
    sol = join(run, 'repair', `a${n}`, 'solution')
  }
  const sum = (k) => attempts.reduce((s, a) => s + (a[k] ?? 0), 0)
  const result = { fixed: last.solved, attempts, costUsd: sum('costUsd'), durationS: sum('durationS'), output: attempts.reduce((s, a) => s + a.usage.output, 0) }
  writeJson(join(run, 'repair.json'), result)
  console.log(`${meta.id}: fixed=${result.fixed} attempts=${attempts.length} cost=$${result.costUsd.toFixed(3)} ${Math.round(result.durationS)}s`)
}

const failed = []
for (const lang of readdirSync(RUNS, { withFileTypes: true }).filter((e) => e.isDirectory())) {
  for (const task of readdirSync(join(RUNS, lang.name))) {
    if (args.tasks && !String(args.tasks).split(',').includes(task)) continue
    for (const rep of readdirSync(join(RUNS, lang.name, task))) {
      const run = join(RUNS, lang.name, task, rep)
      const v = existsSync(join(run, 'verify.json')) && readJson(join(run, 'verify.json'))
      if (v && !v.solved && (args.force || !existsSync(join(run, 'repair.json')))) failed.push(run)
    }
  }
}
console.log(`${failed.length} runs failed round 3`)
await pool(failed, Number(args.jobs), repair)
