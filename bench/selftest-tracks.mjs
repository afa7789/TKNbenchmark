// Proves the specialised-track verifiers are sound: each language's reference solution passes its
// task's suite, and the untouched template (placeholders left in) fails it. Needs the toolchains, so
// it is not part of CI. node bench/selftest-tracks.mjs [--tasks lists,isort]
import { spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT, WORK, TASKS, trackLangs } from './config.mjs'
import { copyFiles, list, parseArgs, solutionFiles } from './lib.mjs'

const args = parseArgs(process.argv.slice(2), {})

async function check(task, lang, variant) {
  const taskDir = join(ROOT, 'bench', 'tasks', task)
  const src = join(taskDir, variant, lang)
  const dir = join(WORK, 'selftest-tracks', `${task}-${lang}-${variant}`)
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  copyFiles(src, dir, solutionFiles(src))
  copyFileSync(join(ROOT, 'bench', 'harness', 'check.mjs'), join(dir, 'check.mjs'))
  const { hidden } = await import(join(taskDir, 'cases.mjs'))
  writeFileSync(join(dir, 'cases.json'), JSON.stringify(hidden(lang)))
  if (!existsSync(join(dir, 'build.sh'))) writeFileSync(join(dir, 'build.sh'), 'true\n')
  const r = spawnSync('node', ['check.mjs', '--json'], { cwd: dir, encoding: 'utf8', timeout: 900000 })
  return JSON.parse(r.stdout.trim().split('\n').at(-1) || '{"pass":0,"total":0,"results":[]}')
}

let failed = 0
const tasks = list(args.tasks, Object.fromEntries(Object.entries(TASKS).filter(([, t]) => t.track && t.kind !== 'stdio')))
for (const task of tasks) {
  for (const lang of trackLangs(TASKS[task].track)) {
    const ref = await check(task, lang, 'reference')
    const tpl = existsSync(join(ROOT, 'bench', 'tasks', task, 'templates', lang)) ? await check(task, lang, 'templates') : null
    const refOk = ref.total > 0 && ref.pass === ref.total
    const tplOk = !tpl || tpl.pass < tpl.total
    console.log(`${task}/${lang}: reference ${ref.pass}/${ref.total}${tpl ? `, template ${tpl.pass}/${tpl.total} (must fail)` : ''}`)
    if (!refOk) console.log('   ', ref.results.filter((x) => !x.ok).map((x) => `${x.name}: ${x.why}`).join(' | '))
    if (!refOk || !tplOk) failed++
  }
}
process.exit(failed ? 1 : 0)
