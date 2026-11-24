// Proves the front-end verifier accepts correct code: reference components must pass their checks.
// Not part of CI (needs npm + Chromium). node bench/selftest-front.mjs
import { join } from 'node:path'
import { ROOT } from './config.mjs'
import { verifyFront } from './verify-front.mjs'

const REF = join(ROOT, 'bench', 'front-ref')
const EXPECT = [
  ['react', 'ui', null],
  ['react', 'shop', null],
  ['vue', 'ui', ['hello', 'counter', 'no-runtime-errors']],
  ['svelte', 'ui', ['hello', 'counter', 'no-runtime-errors']],
]

let failed = 0
for (const [fw, task, only] of EXPECT) {
  const r = await verifyFront(join(REF, fw, task), fw, task, `selftest-${fw}-${task}`)
  const bad = r.cases.filter((c) => !c.ok && (!only || only.includes(c.name)))
  if (!r.buildOk || bad.length) {
    failed++
    console.log(`  ✖ ${fw}/${task}: ${r.buildLog || bad.map((c) => c.why).join('; ')}`)
  }
}
process.exit(failed ? 1 : 0)
