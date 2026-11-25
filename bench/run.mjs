// Agent phase: one isolated headless Claude Code run per (language, task, repeat).
// node bench/run.mjs [--langs rust,zig] [--tasks lru] [--reps 3] [--jobs 4]
// TKN_ARM=skills runs the skills arm into runs-skills/ (see config.mjs).
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { LANGS, FRONTENDS, TASKS, MODEL, EFFORT, RUNS, WORK, MAIN_LANGS, ARM, BASE_RUNS, CLAUDE_BIN, SKILLS, prompt, runDir, runId, trackLangs } from './config.mjs'
import { prepareWorkdir, runAgent } from './agent.mjs'
import { copyFiles, firstLine, list, parseArgs, pool, readJson, shortSha, solutionFiles, writeJson } from './lib.mjs'
import { parseTranscript } from './transcript.mjs'

const args = parseArgs(process.argv.slice(2), { reps: '3', jobs: '4' })
const versions = Object.fromEntries(Object.entries(LANGS).map(([k, l]) => [k, firstLine(l.version)]))
versions.claude = firstLine([CLAUDE_BIN, '--version'])

// New runs (a new language, or another arm) join the published ones only on the same toolchains and
// Claude Code; a language the baseline lacks is added. A fresh baseline starts from an empty runs/.
function requireBaselineToolchains(now) {
  const file = join(BASE_RUNS, 'toolchains.json')
  const base = existsSync(file) ? readJson(file) : {}
  const drift = Object.keys(base).filter((k) => base[k] !== now[k]).map((k) => `  ${k}: ${base[k]} → ${now[k]}`)
  if (!drift.length) return
  console.error(`✖ arm "${ARM}" must use the baseline's toolchains (TKN_CLAUDE pins Claude Code):\n${drift.join('\n')}`)
  process.exit(1)
}

requireBaselineToolchains(versions)
writeJson(join(RUNS, 'toolchains.json'), versions)

const skillSha = (lang) => (ARM === 'skills' ? shortSha(readFileSync(join(SKILLS, lang, 'SKILL.md'))) : null)
// In the skills arm the agent must be offered its language's skill and nothing else.
const wrongSkills = (lang, offered) => ARM === 'skills' && offered.join(',') !== lang

async function runCell({ lang, task, rep }) {
  const out = runDir(lang, task, rep)
  if (existsSync(join(out, 'agent.json')) && !args.force) return
  const id = runId(lang, task, rep)
  const dir = join(WORK, 'agent', id)
  await prepareWorkdir(task, dir, lang)
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
  if (wrongSkills(lang, metrics.skillsOffered)) {
    console.log(`✖ ${id} offered skills [${metrics.skillsOffered}], expected only ${lang}: not recorded`)
    return
  }
  const files = solutionFiles(dir)
  copyFiles(dir, join(out, 'solution'), files)
  writeJson(join(out, 'agent.json'), { id, lang, task, rep, arm: ARM, model: MODEL, effort: EFFORT, skillSha: skillSha(lang), exitCode, wallMs: Date.now() - t0, files, ...metrics })
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

// Front ends, a specialised track's languages, or the main languages.
function languagesFor(task) {
  if (TASKS[task].frontend) return Object.keys(FRONTENDS)
  return TASKS[task].track ? trackLangs(TASKS[task].track) : MAIN_LANGS
}

// Diagonal order: runs in flight at the same time differ in both language and task.
const reps = Number(args.reps)
const tasks = list(args.tasks, TASKS)
const cells = []
for (let rep = 1; rep <= reps; rep++) {
  const batch = []
  tasks.forEach((task, ti) => {
    const langs = languagesFor(task)
    list(args.langs, Object.fromEntries(langs.map((l) => [l, true])))
      .filter((l) => langs.includes(l))
      .forEach((lang, li) => batch.push({ lang, task, rep, key: [(ti - li + tasks.length * 9) % tasks.length, li] }))
  })
  batch.sort((a, b) => a.key[0] - b.key[0] || a.key[1] - b.key[1])
  cells.push(...batch)
}
console.log(`${cells.length} runs, ${args.jobs} at a time, work dir ${WORK}`)
await pool(cells, Number(args.jobs), runCell)
