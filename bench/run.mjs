// Agent phase: one isolated headless Claude Code run per (language, task, repeat).
// node bench/run.mjs [--langs rust,zig] [--tasks lru] [--reps 3] [--jobs 4]
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { LANGS, FRONTENDS, TASKS, MODEL, EFFORT, RUNS, WORK, prompt, runDir, runId } from './config.mjs'
import { prepareWorkdir, runAgent } from './agent.mjs'
import { copyFiles, firstLine, list, parseArgs, pool, readJson, solutionFiles, writeJson } from './lib.mjs'
import { parseTranscript } from './transcript.mjs'

const args = parseArgs(process.argv.slice(2), { reps: '3', jobs: '4' })
const versions = Object.fromEntries(Object.entries(LANGS).map(([k, l]) => [k, firstLine(l.version)]))
versions.claude = firstLine(['claude', '--version'])
writeJson(join(RUNS, 'toolchains.json'), versions)

async function runCell({ lang, task, rep }) {
  const out = runDir(lang, task, rep)
  if (existsSync(join(out, 'agent.json')) && !args.force) return
  const id = runId(lang, task, rep)
  const dir = join(WORK, 'agent', id)
  await prepareWorkdir(task, dir)
  rmSync(out, { recursive: true, force: true })
  mkdirSync(out, { recursive: true })
  const transcript = join(out, 'transcript.jsonl')
  console.log(`▶ ${id}`)
  const t0 = Date.now()
  const exitCode = await runAgent(dir, prompt(task, lang, versions[lang]), transcript)
  const metrics = parseTranscript(readFileSync(transcript, 'utf8'))
  if (metrics.terminalReason === 'api_error') {
    console.log(`✖ ${id} API error (rate limit / billing): not recorded, rerun later. ${metrics.reply}`)
    return
  }
  const files = solutionFiles(dir)
  copyFiles(dir, join(out, 'solution'), files)
  writeJson(join(out, 'agent.json'), { id, lang, task, rep, model: MODEL, effort: EFFORT, exitCode, wallMs: Date.now() - t0, files, ...metrics })
  console.log(`✔ ${id} cost=$${metrics.costUsd?.toFixed(3)} out=${metrics.usage.output} turns=${metrics.turns} check=${JSON.stringify(metrics.lastCheck)}`)
}

// Recompute metrics from saved transcripts after the parser changes. Keeps everything else.
function reparse() {
  for (const lang of readdirSync(RUNS, { withFileTypes: true }).filter((e) => e.isDirectory())) {
    for (const task of readdirSync(join(RUNS, lang.name))) {
      for (const rep of readdirSync(join(RUNS, lang.name, task))) {
        const dir = join(RUNS, lang.name, task, rep)
        if (!existsSync(join(dir, 'transcript.jsonl')) || !existsSync(join(dir, 'agent.json'))) continue
        const old = readJson(join(dir, 'agent.json'))
        writeJson(join(dir, 'agent.json'), { ...old, ...parseTranscript(readFileSync(join(dir, 'transcript.jsonl'), 'utf8')) })
      }
    }
  }
}

if (args.reparse) {
  reparse()
  process.exit(0)
}

// Diagonal order: runs in flight at the same time differ in both language and task.
const reps = Number(args.reps)
const tasks = list(args.tasks, TASKS)
const cells = []
for (let rep = 1; rep <= reps; rep++) {
  const batch = []
  tasks.forEach((task, ti) => {
    const langs = TASKS[task].frontend ? FRONTENDS : LANGS
    list(args.langs, langs)
      .filter((l) => l in langs)
      .forEach((lang, li) => batch.push({ lang, task, rep, key: [(ti - li + tasks.length * 9) % tasks.length, li] }))
  })
  batch.sort((a, b) => a.key[0] - b.key[0] || a.key[1] - b.key[1])
  cells.push(...batch)
}
console.log(`${cells.length} runs, ${args.jobs} at a time, work dir ${WORK}`)
await pool(cells, Number(args.jobs), runCell)
