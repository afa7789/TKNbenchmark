import { genInput } from '../../harness/check.mjs'
import { solve } from './reference.mjs'

const TOL = 1e-6
const lit = (name, stdin) => ({ name, stdin, stdout: solve(Buffer.from(stdin)), tolerance: TOL })
const generated = (name, gen, timeoutMs = 10000) => ({ name, gen, timeoutMs, stdout: solve(genInput(gen)), tolerance: TOL })

export const visible = () => ({
  kind: 'stdio',
  cases: [
    lit('spec-example', '4 1\n0 1\n1 3\n2 5\n3 7\n'),
    lit('two-features', '5 2\n1 2 9.5\n2 1 8.1\n3 4 19.2\n4 3 17.9\n5 5 25.4\n'),
    generated('medium-1k', { type: 'linreg', seed: 1, n: 1000, k: 3 }),
  ],
})

export const hidden = () => ({
  kind: 'stdio',
  cases: [
    ...visible().cases,
    lit('exactly-determined', '3 2\n1 0 2\n0 1 3\n1 1 6\n'),
    lit('negative-and-decimals', '6 1\n-1.5 -2.25\n-0.5 0.75\n0.5 1.5\n1.5 5.25\n2.5 6\n3.5 9.75\n'),
    generated('no-noise', { type: 'linreg', seed: 2, n: 500, k: 4, noise: 0 }),
    generated('many-features', { type: 'linreg', seed: 3, n: 5000, k: 20 }),
    generated('large-200k', { type: 'linreg', seed: 4, n: 200_000, k: 8 }, 20000),
  ],
})
