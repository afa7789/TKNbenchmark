// One headless Claude Code agent in a workdir: the unit every round runs.
import { spawn } from 'node:child_process'
import { createWriteStream, existsSync, mkdirSync, readFileSync, rmSync, copyFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { TASKS, MODEL, EFFORT, RUN_TIMEOUT_MS, ROOT, ARM, AGENT_CLI, BASE_RUNS, CLAUDE_BIN, SKILLS, PORT_FROM } from './config.mjs'
import { claudeEnv, copyFiles, firstLine, killStragglers, readJson, solutionFiles } from './lib.mjs'

// Every round that starts agents (write, repair, skill writing) runs the published run's Claude Code.
const BASE_TOOLCHAINS = join(BASE_RUNS, 'toolchains.json')
if (existsSync(BASE_TOOLCHAINS)) {
  const [want, have] = [readJson(BASE_TOOLCHAINS).claude, firstLine([CLAUDE_BIN, '--version'])]
  if (want !== have) {
    console.error(`✖ Claude Code ${have} ≠ baseline ${want}: set TKN_CLAUDE to the baseline's binary`)
    process.exit(1)
  }
}

// Claude Code keeps auto-memory per working directory; a rerun of the same case must not inherit it.
function forgetMemory(transcript) {
  const init = JSON.parse(readFileSync(transcript, 'utf8').split('\n', 1)[0] || '{}')
  const dir = init.memory_paths?.auto
  if (dir) rmSync(dir, { recursive: true, force: true })
}

// The baseline's working solution of a case: round 3's if it passed, else the repair that fixed it.
export function workingSolution(lang, task, rep) {
  const run = join(BASE_RUNS, lang, task, `r${rep}`)
  if (readJson(join(run, 'verify.json')).solved) return join(run, 'solution')
  const fix = readJson(join(run, 'repair.json'))
  if (!fix.fixed) throw new Error(`${lang}-${task}-r${rep} never worked: nothing to port`)
  return join(run, 'repair', `a${fix.attempts.length}`, 'solution')
}

// Fresh workdir with what the agent may see: SPEC.md, per-language templates (proof statements),
// the language's skill in the skills arm, the program to port in a port arm, plus check.mjs and the
// visible cases for non-front-end tasks. Dot-dirs (.claude/, .source/) never reach solution/.
export async function prepareWorkdir(task, dir, lang, rep) {
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  const taskDir = join(ROOT, 'bench', 'tasks', task)
  copyFileSync(join(taskDir, 'SPEC.md'), join(dir, 'SPEC.md'))
  const templates = join(taskDir, 'templates', lang ?? '')
  if (lang && existsSync(templates)) copyFiles(templates, dir, solutionFiles(templates))
  if (ARM === 'skills') copyFiles(join(SKILLS, lang), join(dir, '.claude', 'skills', lang), ['SKILL.md'])
  if (PORT_FROM) {
    const src = workingSolution(PORT_FROM, task, rep)
    copyFiles(src, join(dir, '.source'), solutionFiles(src))
  }
  if (TASKS[task].frontend) return
  copyFileSync(join(ROOT, 'bench', 'harness', 'check.mjs'), join(dir, 'check.mjs'))
  const { visible } = await import(join(taskDir, 'cases.mjs'))
  writeFileSync(join(dir, 'cases.json'), JSON.stringify(visible(lang), null, 1))
}

// cli: { tools, args, env } — the arm's agent by default; the skill writer passes its own.
export function runAgent(dir, text, transcript, cli = AGENT_CLI) {
  const argv = ['-p', text, '--model', MODEL, '--effort', EFFORT, '--output-format', 'stream-json', '--verbose',
    '--permission-mode', 'bypassPermissions', '--setting-sources', 'project', '--strict-mcp-config',
    '--tools', cli.tools, ...cli.args, '--no-session-persistence', '--max-budget-usd', '10']
  return new Promise((resolve) => {
    const out = createWriteStream(transcript)
    const child = spawn(CLAUDE_BIN, argv, { cwd: dir, env: { ...claudeEnv(), ...cli.env }, stdio: ['ignore', 'pipe', 'pipe'] })
    const stop = () => {
      killStragglers(dir)
      child.kill('SIGKILL')
    }
    const timer = setTimeout(stop, RUN_TIMEOUT_MS)
    // After the final event, give the CLI 15 s to exit; then clear anything the agent left running.
    child.stdout.on('data', (d) => d.includes('"type":"result"') && setTimeout(stop, 15_000).unref())
    child.on('exit', () => killStragglers(dir))
    child.stdout.pipe(out)
    child.stderr.on('data', (d) => process.stderr.write(`[${dir}] ${d}`))
    child.on('close', (code) => {
      clearTimeout(timer)
      out.end(() => {
        forgetMemory(transcript)
        resolve(code)
      })
    })
  })
}
