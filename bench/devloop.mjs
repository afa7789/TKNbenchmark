// Rust's everyday dev loop on the kvhttp solutions: what target/ holds after debug build + release
// build + test build, versus the release-only build that round 3 measures. node bench/devloop.mjs
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { RUNS, WORK } from './config.mjs'
import { copyFiles, duBytes, solutionFiles, writeJson } from './lib.mjs'

const STEPS = [['build'], ['build', '--release'], ['test', '--no-run']]

function cargo(dir, env, args) {
  const t0 = performance.now()
  const r = spawnSync('cargo', args, { cwd: dir, env, encoding: 'utf8', timeout: 20 * 60 * 1000 })
  return { ok: r.status === 0, secs: (performance.now() - t0) / 1000 }
}

for (const rep of readdirSync(join(RUNS, 'rust', 'kvhttp'))) {
  const run = join(RUNS, 'rust', 'kvhttp', rep)
  if (existsSync(join(run, 'devloop.json'))) continue
  const dir = join(WORK, 'devloop', rep)
  const home = `${dir}.home`
  rmSync(dir, { recursive: true, force: true })
  rmSync(home, { recursive: true, force: true })
  mkdirSync(home, { recursive: true })
  copyFiles(join(run, 'solution'), dir, solutionFiles(join(run, 'solution')))
  const env = { ...process.env, CARGO_HOME: join(home, '.cargo') }
  const steps = STEPS.map((args) => ({ step: `cargo ${args.join(' ')}`, ...cargo(dir, env, args), targetBytes: duBytes(join(dir, 'target')) }))
  const out = { steps, targetBytes: duBytes(join(dir, 'target')), registryBytes: duBytes(join(home, '.cargo')) }
  writeJson(join(run, 'devloop.json'), out)
  console.log(`rust-kvhttp-${rep}: target ${(out.targetBytes / 1e6).toFixed(0)} MB, registry ${(out.registryBytes / 1e6).toFixed(0)} MB`, steps.map((s) => `${s.step}=${s.ok}`).join(' '))
  rmSync(dir, { recursive: true, force: true })
  rmSync(home, { recursive: true, force: true })
}
