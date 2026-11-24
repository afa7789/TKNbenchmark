import { genInput, sha256 } from '../../harness/check.mjs'
import { solve } from './reference.mjs'

const lit = (name, lines) => {
  const stdin = lines.join('\n') + '\n'
  return { name, stdin, stdout: solve(Buffer.from(stdin)) }
}

function generated(name, gen, timeoutMs) {
  const out = solve(genInput(gen))
  return { name, gen, timeoutMs, stdoutSha256: sha256(Buffer.from(out, 'latin1')) }
}

const deep = '('.repeat(500) + '1' + ')'.repeat(500)

export const visible = () => ({
  kind: 'stdio',
  cases: [
    lit('spec-example', ['1 + 2 * 3', '-7 / 2', '(1 + 2', '9223372036854775807 + 1']),
    lit('precedence', ['(1 + 2) * 3', '1 + 2 * 3 - 4 / 2 % 3', '2*(3+4)*5', '10 - 4 - 3']),
    lit('division-and-remainder', ['7 / 2', '-7 % 3', '7 % -3', '0 / 5', '1 / 0', '5 % 0']),
    lit('unary-minus', ['--5', '2 * -3', '1 - -2', '-(2 + 3)']),
    lit('syntax-errors', ['1 +', 'abc', '()', '1 2', '+1']),
    lit('blank-lines', ['', '  42  ', '\t', '1+1']),
  ],
})

export const hidden = () => ({
  kind: 'stdio',
  cases: [
    ...visible().cases,
    lit('literal-overflow', ['9223372036854775808', '-9223372036854775808', '9223372036854775807', '00012']),
    lit('int64-min', ['-9223372036854775807 - 1', '(-9223372036854775807 - 1) / -1', '(-9223372036854775807 - 1) % -1', '-(-9223372036854775807 - 1)']),
    lit('mul-overflow', ['3037000499 * 3037000499', '3037000500 * 3037000500', '-3037000500 * 3037000500', '4294967296 * 4294967296']),
    lit('sub-overflow', ['-9223372036854775807 - 2', '0 - 9223372036854775807', '9223372036854775807 - -1']),
    lit('parens', ['(1', '1)', '((2))', '(()', '(1)(2)', deep]),
    lit('whitespace', ['\t1\t+\t2', '  -  3', '1  *  ( 2 + 3 )']),
    lit('operators-misused', ['1 + + 2', '1 * / 2', '*', '-', '1 %', '7 %% 2']),
    lit('other-chars', ['1.5 + 1', '2^3', '1,000', '0x10', '3 + x']),
    generated('random-20k-lines', { type: 'calc', seed: 5, lines: 20_000 }, 10000),
  ],
})
