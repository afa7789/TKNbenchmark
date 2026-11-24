import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const MIN = -(2n ** 63n)
const MAX = 2n ** 63n - 1n

class CalcError extends Error {}

function fit(v) {
  if (v < MIN || v > MAX) throw new CalcError('overflow')
  return v
}

function tokenize(s) {
  const re = /[ \t]*(?:(\d+)|([-+*/%()])|$)/y
  const tokens = []
  for (let pos = 0; pos < s.length; pos = re.lastIndex) {
    re.lastIndex = pos
    const m = re.exec(s)
    if (!m) throw new CalcError('syntax')
    if (m[1]) tokens.push(fit(BigInt(m[1])))
    else if (m[2]) tokens.push(m[2])
  }
  return tokens
}

const BINARY = {
  '+': (a, b) => fit(a + b),
  '-': (a, b) => fit(a - b),
  '*': (a, b) => fit(a * b),
  '/': (a, b) => {
    if (b === 0n) throw new CalcError('div0')
    return fit(a / b)
  },
  '%': (a, b) => {
    if (b === 0n) throw new CalcError('div0')
    return a % b
  },
}

function parser(tokens) {
  let i = 0
  const peek = () => tokens[i]
  const next = () => tokens[i++]
  function primary() {
    const t = next()
    if (typeof t === 'bigint') return t
    if (t !== '(') throw new CalcError('syntax')
    const v = expr()
    if (next() !== ')') throw new CalcError('syntax')
    return v
  }
  function unary() {
    if (peek() !== '-') return primary()
    next()
    return fit(-unary())
  }
  function chain(operand, ops) {
    let v = operand()
    while (ops.includes(peek())) {
      const op = next()
      v = BINARY[op](v, operand())
    }
    return v
  }
  const term = () => chain(unary, ['*', '/', '%'])
  const expr = () => chain(term, ['+', '-'])
  return { expr, done: () => i === tokens.length }
}

export function evaluate(line) {
  try {
    const p = parser(tokenize(line))
    const v = p.expr()
    return p.done() ? String(v) : 'error'
  } catch (e) {
    if (e instanceof CalcError) return 'error'
    throw e
  }
}

export function solve(buf) {
  return buf
    .toString('latin1')
    .split('\n')
    .filter((l) => !/^[ \t]*$/.test(l))
    .map(evaluate)
    .join('\n')
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = solve(readFileSync(0))
  process.stdout.write(out ? out + '\n' : '')
}
