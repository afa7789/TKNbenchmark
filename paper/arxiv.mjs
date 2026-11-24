// Builds the arXiv upload: paper/arxiv/{main.tex,data.tex} with comment lines stripped (arXiv
// archives the source forever), test-compiles it, and packs paper/arxiv.tar.gz.
import { spawnSync } from 'node:child_process'
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from '../bench/config.mjs'

const src = join(ROOT, 'paper')
const out = join(src, 'arxiv')
const strip = (text) =>
  text
    .split('\n')
    .filter((l) => !/^\s*%/.test(l))
    .join('\n')

rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'main.tex'), strip(readFileSync(join(src, 'paper.tex'), 'utf8')))
writeFileSync(join(out, 'data.tex'), strip(readFileSync(join(src, 'data.tex'), 'utf8')))

const tex = spawnSync('tectonic', ['main.tex'], { cwd: out, encoding: 'utf8' })
if (tex.status !== 0) {
  console.error(tex.stderr.slice(-2000))
  process.exit(1)
}
rmSync(join(out, 'main.pdf'))
spawnSync('tar', ['-czf', join(src, 'arxiv.tar.gz'), '-C', out, 'main.tex', 'data.tex'])
console.log('paper/arxiv.tar.gz: main.tex + data.tex (compiles)')
