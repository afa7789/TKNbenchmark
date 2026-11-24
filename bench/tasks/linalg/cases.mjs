import { genInput } from '../../harness/check.mjs'
import { solve } from './reference.mjs'

const TOL = 1e-6
const lit = (name, stdin) => ({ name, stdin, stdout: solve(Buffer.from(stdin)), tolerance: TOL })
const generated = (name, gen, timeoutMs = 10000) => ({ name, gen, timeoutMs, stdout: solve(genInput(gen)), tolerance: TOL })

export const visible = () => ({
  kind: 'stdio',
  cases: [
    lit('spec-example', '2\n2 0\n0 8\n2 4\n'),
    lit('three-by-three', '3\n4 1 0\n1 3 1\n0 1 2\n1 2 3\n'),
    generated('medium-20', { type: 'spd', seed: 1, n: 20 }),
  ],
})

export const hidden = () => ({
  kind: 'stdio',
  cases: [
    ...visible().cases,
    lit('one-by-one', '1\n5\n10\n'),
    lit('diagonal', '4\n1 0 0 0\n0 2 0 0\n0 0 3 0\n0 0 0 4\n4 4 3 8\n'),
    lit('repeated-eigenvalue', '3\n2 0 0\n0 2 0\n0 0 5\n1 1 1\n'),
    generated('medium-60', { type: 'spd', seed: 2, n: 60 }),
    generated('large-300', { type: 'spd', seed: 3, n: 300 }, 20000),
  ],
})
