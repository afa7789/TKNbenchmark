// Skills arm, step 0: one Claude Code skill per language. A fresh agent researches what practitioners
// use for the installed version, checks every claim against the toolchain and writes the body
// (prompt: skillPrompt in config.mjs); the harness adds the same front matter to every skill.
// node bench/skills.mjs [--langs zig,rust] [--force] [--jobs 4]
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { CLAUDE_BIN, FRONTENDS, LANGS, SKILLS, SKILL_MAX_BYTES, WORK, skillPrompt } from './config.mjs'
import { runAgent } from './agent.mjs'
import { firstLine, list, parseArgs, pool, readJson, shortSha, writeJson } from './lib.mjs'
import { parseTranscript } from './transcript.mjs'

const args = parseArgs(process.argv.slice(2), { jobs: '4' })
const WRITER = { tools: 'Bash,Read,Edit,Write,WebSearch,WebFetch', args: [], env: {} }
const META = join(SKILLS, 'meta.json')
const claudeVersion = firstLine([CLAUDE_BIN, '--version'])
// The writer must not learn the benchmark's tasks: its own repo and results site are off limits.
const LEAK_RE = /tknbenchmark|afa7789/i
// Reported for review, not rejected: words that would tie a skill to one of the benchmark's tasks.
const TASK_RE = /wordfreq|word.frequenc|\bLRU\b|kvhttp|key.value (server|store)|expression evaluat|sudoku|range check|vesting|insertion sort|least.squares|log.determinant|shopping/gi

const versionText = (lang) =>
  LANGS[lang] ? firstLine(LANGS[lang].version) : Object.entries(FRONTENDS[lang].pins).map(([p, v]) => `${p} ${v}`).join(', ')

function frontMatter(lang, version) {
  const { label } = LANGS[lang] ?? FRONTENDS[lang]
  const description = `Version-correct, idiomatic ${label} for the installed toolchain (${version}): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing ${label} code.`
  return `---\nname: ${lang}\ndescription: ${JSON.stringify(description)}\n---\n\n`
}

const readOr = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '')

// What the writer sent to its tools (URLs fetched, commands run); search results may list anything.
const toolInputs = (text) =>
  text.split('\n').filter(Boolean).flatMap((l) => JSON.parse(l).message?.content ?? []).filter((b) => b.type === 'tool_use').map((b) => JSON.stringify(b.input))

function problems(m, body, sources, inputs) {
  const out = []
  const bytes = Buffer.byteLength(body)
  if (m.terminalReason === 'api_error') out.push(`API error: ${m.reply}`)
  if (!bytes) out.push('no SKILL.md')
  if (bytes > SKILL_MAX_BYTES) out.push(`SKILL.md body is ${bytes} bytes (max ${SKILL_MAX_BYTES})`)
  if (LEAK_RE.test(sources) || inputs.some((i) => LEAK_RE.test(i))) out.push("used the benchmark's own repo or site")
  return out
}

function record(lang, entry) {
  const meta = existsSync(META) ? readJson(META) : {}
  meta[lang] = entry
  writeJson(META, Object.fromEntries(Object.entries(meta).sort(([a], [b]) => a.localeCompare(b))))
}

async function writeSkill(lang) {
  const out = join(SKILLS, lang)
  if (existsSync(join(out, 'SKILL.md')) && !args.force) return
  const dir = join(WORK, 'skillgen', lang)
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  mkdirSync(out, { recursive: true })
  const version = versionText(lang)
  const transcript = join(out, 'transcript.jsonl')
  console.log(`▶ ${lang} (${version})`)
  await runAgent(dir, skillPrompt(lang, version), transcript, WRITER)
  const text = readFileSync(transcript, 'utf8')
  const m = parseTranscript(text)
  const body = readOr(join(dir, 'SKILL.md')).replace(/^---\n[\s\S]*?\n---\n/, '').trim()
  const sources = readOr(join(dir, 'SOURCES.md'))
  const bad = problems(m, body, sources, toolInputs(text))
  const skill = `${frontMatter(lang, version)}${body}\n`
  if (!bad.length) {
    writeFileSync(join(out, 'SKILL.md'), skill)
    writeFileSync(join(out, 'SOURCES.md'), sources)
  }
  const summary = { ok: !bad.length, problems: bad, taskTerms: [...new Set(body.match(TASK_RE))], bodyBytes: Buffer.byteLength(body), costUsd: m.costUsd }
  record(lang, { version, claude: claudeVersion, ...summary, sha: shortSha(skill), output: m.usage.output, turns: m.turns, durationS: m.durationMs / 1000, tools: m.tools })
  console.log(`${lang}: ${JSON.stringify(summary)}  (writer's dir: ${dir})`)
}

const langs = list(args.langs, { ...LANGS, ...FRONTENDS })
console.log(`${langs.length} skills, ${args.jobs} at a time, Claude Code ${claudeVersion}`)
await pool(langs, Number(args.jobs), writeSkill)
