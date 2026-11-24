// Shared case builder for the theorem-proving track. The protected parts (definitions and
// statements) are read from each language's template, so they cannot drift from what the agent sees.
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

export const PROOF_LANGS = {
  lean: {
    ext: '.lean',
    run: (f) => ['lean', f],
    placeholder: 'sorry',
    comments: ['--[^\\n]*', '/-[\\s\\S]*?-/'],
    forbid: '\\b(sorry|admit|axiom|unsafe|implemented_by|extern|native_decide)\\b',
    tail: /(:=\s*by|:=)$/,
  },
  rocq: {
    ext: '.v',
    run: (f) => ['coqc', f],
    placeholder: 'Admitted.',
    comments: ['\\(\\*[\\s\\S]*?\\*\\)'],
    forbid: '\\b(Admitted|admit|Axiom|Axioms|Parameter|Parameters|Conjecture|give_up)\\b',
    tail: /Proof\.$/,
  },
  dafny: {
    ext: '.dfy',
    run: (f) => ['dafny', 'verify', f],
    placeholder: 'assume false;',
    comments: ['//[^\\n]*', '/\\*[\\s\\S]*?\\*/'],
    forbid: '\\bassume\\b|\\{:axiom\\}|\\{:verify\\s+false\\}|\\{:extern',
    tail: /\{$/,
  },
}

const norm = (s) => s.replace(/\s+/g, ' ').trim()

export function proofSuite(taskDir, file, lang) {
  const L = PROOF_LANGS[lang]
  const name = `${file}${L.ext}`
  let template = readFileSync(join(taskDir, 'templates', lang, name), 'utf8')
  for (const c of L.comments) template = template.replace(new RegExp(c, 'g'), '')
  const chunks = template
    .split(L.placeholder)
    .join('\n\n')
    .split(/\n\s*\n/)
    .map((c) => norm(c).replace(L.tail, '').trim())
    .filter((c) => c.replace(/[{}]/g, '').trim())
  const scan = { ext: L.ext, comments: L.comments }
  return {
    kind: 'proof',
    cases: [
      { name: 'proofs-check', run: L.run(name), timeoutMs: 300000 },
      { name: 'no-escape-hatches', scan, forbid: L.forbid },
      ...chunks.map((c, i) => ({ name: `unchanged-${i + 1}`, scan, contains: c })),
    ],
  }
}
