// Static size of each solution in tokens.
// - opus: Claude Opus 5.5 tokenizer. Measured as the input-token delta of a headless `claude -p`
//   call with the code vs. an empty baseline (same numbers count_tokens would give; works on a
//   Claude Code login without API credit). Results are cached in runs/token-cache.json.
// - cl100k: OpenAI cl100k_base, only to compare with the HackerNoon series, which used it.
// node bench/count.mjs [--force] [--jobs 4]
import { spawn } from 'node:child_process'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { join } from 'node:path'
import { getEncoding } from 'js-tiktoken'
import { CLAUDE_BIN, MODEL, RUNS, TASKS } from './config.mjs'
import { claudeEnv, isCounted, parseArgs, pool, readJson, solutionFiles, writeJson } from './lib.mjs'

const args = parseArgs(process.argv.slice(2), { jobs: '4' })
const CACHE = join(RUNS, 'token-cache.json')
const cache = existsSync(CACHE) ? readJson(CACHE) : {}
const enc = getEncoding('cl100k_base')
const wrap = (text) => `<code>\n${text}\n</code>`

function inputTokens(text) {
  const argv = ['-p', '--model', MODEL, '--effort', 'low', '--output-format', 'json', '--tools', '', '--system-prompt', 'Reply with OK.',
    '--setting-sources', 'project', '--strict-mcp-config', '--no-session-persistence']
  return new Promise((resolve, reject) => {
    const child = spawn(CLAUDE_BIN, argv, { env: claudeEnv(), stdio: ['pipe', 'pipe', 'inherit'] })
    let out = ''
    child.stdout.on('data', (d) => (out += d))
    child.on('close', () => {
      try {
        const u = JSON.parse(out).usage
        resolve(u.input_tokens + u.cache_creation_input_tokens + u.cache_read_input_tokens)
      } catch (e) {
        reject(new Error(`token count failed: ${e.message} ${out.slice(0, 300)}`))
      }
    })
    child.stdin.end(text)
  })
}

async function opusTokens(text) {
  const key = createHash('sha256').update(text).digest('hex')
  cache.baseline ??= await inputTokens(wrap(''))
  cache[key] ??= (await inputTokens(wrap(text))) - cache.baseline
  return cache[key]
}

async function measure(text) {
  return { opus: await opusTokens(text), cl100k: enc.encode(text).length, chars: text.length, lines: text.split('\n').length }
}

async function countRun(run) {
  const meta = readJson(join(run, 'agent.json'))
  const sol = join(run, 'solution')
  const files = solutionFiles(sol).filter((f) => isCounted(sol, f))
  const texts = files.map((f) => readFileSync(join(sol, f), 'utf8'))
  const perFile = TASKS[meta.task].frontend ? await Promise.all(texts.map(measure)) : []
  const total = await measure(texts.join('\n'))
  writeJson(join(run, 'tokens.json'), { ...total, files: files.map((path, i) => ({ path, ...perFile[i] })) })
  writeJson(CACHE, cache)
  console.log(`${meta.id}: opus=${total.opus} cl100k=${total.cl100k} files=${files.length}`)
}

const runs = []
for (const lang of readdirSync(RUNS, { withFileTypes: true }).filter((e) => e.isDirectory())) {
  for (const task of readdirSync(join(RUNS, lang.name))) {
    for (const rep of readdirSync(join(RUNS, lang.name, task))) runs.push(join(RUNS, lang.name, task, rep))
  }
}
const todo = runs.filter((r) => existsSync(join(r, 'agent.json')) && (args.force || !existsSync(join(r, 'tokens.json'))))
cache.baseline ??= await inputTokens(wrap(''))
await pool(todo, Number(args.jobs), countRun)
