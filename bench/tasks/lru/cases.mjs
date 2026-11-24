import { genInput, sha256 } from '../../harness/check.mjs'
import { solve } from './reference.mjs'

const lit = (name, lines, trailing = true) => {
  const stdin = lines.join('\n') + (trailing ? '\n' : '')
  return { name, stdin, stdout: solve(Buffer.from(stdin)) }
}

function generated(name, gen, timeoutMs) {
  const out = solve(genInput(gen))
  return { name, gen, timeoutMs, stdoutSha256: sha256(Buffer.from(out, 'latin1')) }
}

export const visible = () => ({
  kind: 'stdio',
  cases: [
    lit('spec-example', ['2', 'SET a 1', 'SET b 2', 'GET a', 'SET c 3', 'GET b', 'SIZE']),
    lit('overwrite-refreshes', ['2', 'SET a 1', 'SET b 2', 'SET a 9', 'SET c 3', 'GET a', 'GET b', 'GET c']),
    lit('del-and-size', ['3', 'SET x 1', 'DEL x', 'DEL x', 'SIZE', 'GET x']),
    lit('capacity-one', ['1', 'SET a 1', 'SET b 2', 'GET a', 'GET b', 'SIZE']),
    generated('medium-50k-ops', { type: 'lru', seed: 3, ops: 50_000, cap: 500, keys: 2000 }, 5000),
  ],
})

export const hidden = () => ({
  kind: 'stdio',
  cases: [
    ...visible().cases,
    lit('get-refreshes', ['2', 'SET a 1', 'SET b 2', 'GET a', 'SET c 3', 'GET a', 'GET b', 'GET c']),
    lit('overwrite-keeps-size', ['5', 'SET a 1', 'SET a 2', 'SET a 3', 'SIZE', 'GET a']),
    lit('del-then-set', ['2', 'SET a 1', 'SET b 2', 'DEL a', 'SET c 3', 'GET b', 'GET c', 'SIZE']),
    lit('no-trailing-newline', ['3', 'SET k v', 'GET k'], false),
    lit('only-capacity', ['10']),
    lit('long-tokens', ['2', `SET ${'k'.repeat(64)} ${'v'.repeat(64)}`, `GET ${'k'.repeat(64)}`]),
    lit('punctuation-keys', ['2', 'SET a:b {"x":1}', 'GET a:b', 'GET a', 'DEL a:b']),
    generated('large-1m-ops', { type: 'lru', seed: 11, ops: 1_000_000, cap: 50_000, keys: 200_000 }, 10000),
    generated('large-tiny-cap', { type: 'lru', seed: 12, ops: 300_000, cap: 1, keys: 3 }, 10000),
  ],
})
