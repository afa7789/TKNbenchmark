// One headless Claude Code agent in a workdir: the unit every round runs.
import { spawn } from 'node:child_process'
import { createWriteStream, existsSync, mkdirSync, rmSync, copyFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { TASKS, MODEL, EFFORT, RUN_TIMEOUT_MS, ROOT, ARM, AGENT_CLI, CLAUDE_BIN, SKILLS } from './config.mjs'
import { claudeEnv, copyFiles, killStragglers, solutionFiles } from './lib.mjs'

// Fresh workdir with what the agent may see: SPEC.md, per-language templates (proof statements),
// the language's skill in the skills arm, plus check.mjs and the visible cases for non-front-end tasks.
// .claude/ is a dot-dir, so solutionFiles never copies the skill into solution/.
export async function prepareWorkdir(task, dir, lang) {
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  const taskDir = join(ROOT, 'bench', 'tasks', task)
  copyFileSync(join(taskDir, 'SPEC.md'), join(dir, 'SPEC.md'))
  const templates = join(taskDir, 'templates', lang ?? '')
  if (lang && existsSync(templates)) copyFiles(templates, dir, solutionFiles(templates))
  if (ARM === 'skills') copyFiles(join(SKILLS, lang), join(dir, '.claude', 'skills', lang), ['SKILL.md'])
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
      out.end(() => resolve(code))
    })
  })
}
