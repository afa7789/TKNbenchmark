// Proves the verifier is sound: each task's JS reference must pass its own visible + hidden suites.
import { spawnSync } from 'node:child_process'
import { mkdirSync, rmSync, writeFileSync, copyFileSync, chmodSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT, WORK, TASKS } from './config.mjs'

let failed = 0
for (const [task, t] of Object.entries(TASKS)) {
  if (!['stdio', 'http'].includes(t.kind)) continue
  const taskDir = join(ROOT, 'bench', 'tasks', task)
  const dir = join(WORK, 'selftest', task)
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  writeFileSync(join(dir, 'app'), `#!/bin/sh\nexec node ${JSON.stringify(join(taskDir, 'reference.mjs'))} "$@"\n`)
  chmodSync(join(dir, 'app'), 0o755)
  writeFileSync(join(dir, 'build.sh'), 'true\n')
  copyFileSync(join(ROOT, 'bench', 'harness', 'check.mjs'), join(dir, 'check.mjs'))
  const cases = await import(join(taskDir, 'cases.mjs'))
  for (const suite of ['visible', 'hidden']) {
    writeFileSync(join(dir, `${suite}.json`), JSON.stringify(cases[suite]()))
    const r = spawnSync('node', ['check.mjs', '--cases', `${suite}.json`], { cwd: dir, encoding: 'utf8' })
    const line = r.stdout.trim().split('\n').at(-1)
    console.log(`${task}/${suite}: ${line}`)
    if (r.status !== 0) {
      failed++
      console.log(r.stdout)
    }
  }
}
process.exit(failed ? 1 : 0)
