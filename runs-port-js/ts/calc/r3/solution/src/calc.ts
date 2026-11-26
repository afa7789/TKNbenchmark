// 64-bit signed integer expression evaluator. Reads expressions from stdin,
// one per line, and prints each value or `error`.
//
// The parser is an iterative operator-precedence (shunting-yard) evaluator so
// that arbitrarily deep nesting cannot overflow the call stack.

import { readFileSync } from 'node:fs'

const INT64_MIN = -(2n ** 63n)
const INT64_MAX = 2n ** 63n - 1n

/** Raised for any condition that makes a line print `error`. */
class CalcError extends Error {}

function fail(): never {
  throw new CalcError()
}

function checked(v: bigint): bigint {
  return v < INT64_MIN || v > INT64_MAX ? fail() : v
}

const CH = {
  TAB: 9,
  SPACE: 32,
  PERCENT: 37,
  LPAREN: 40,
  RPAREN: 41,
  STAR: 42,
  PLUS: 43,
  MINUS: 45,
  SLASH: 47,
  ZERO: 48,
  NINE: 57,
} as const

type BinaryOp = typeof CH.PLUS | typeof CH.MINUS | typeof CH.STAR | typeof CH.SLASH | typeof CH.PERCENT

/** Operator-stack entries: an open parenthesis, unary negation, or a binary operator. */
const LPAREN_MARK = 0
const NEG_MARK = 1
type StackOp = typeof LPAREN_MARK | typeof NEG_MARK | BinaryOp

const NEG_PREC = 3

function binaryPrec(c: number): number | undefined {
  switch (c) {
    case CH.PLUS:
    case CH.MINUS:
      return 1
    case CH.STAR:
    case CH.SLASH:
    case CH.PERCENT:
      return 2
    default:
      return undefined
  }
}

function precOf(op: StackOp): number {
  if (op === NEG_MARK) return NEG_PREC
  if (op === LPAREN_MARK) return 0
  return binaryPrec(op) ?? 0
}

function applyBinary(op: BinaryOp, a: bigint, b: bigint): bigint {
  switch (op) {
    case CH.PLUS:
      return checked(a + b)
    case CH.MINUS:
      return checked(a - b)
    case CH.STAR:
      return checked(a * b)
    case CH.SLASH:
      return b === 0n ? fail() : checked(a / b)
    case CH.PERCENT:
      return b === 0n ? fail() : a % b
  }
}

const isDigit = (c: number): boolean => c >= CH.ZERO && c <= CH.NINE

/** Evaluate one expression line; returns its value or throws CalcError. */
export function evaluate(line: string): bigint {
  const values: bigint[] = []
  const ops: StackOp[] = []
  let expectOperand = true

  const pop = (): bigint => values.pop() ?? fail()

  const reduceTop = (): void => {
    const op = ops.pop()
    if (op === undefined || op === LPAREN_MARK) fail()
    if (op === NEG_MARK) {
      values.push(checked(-pop()))
    } else {
      const b = pop()
      const a = pop()
      values.push(applyBinary(op, a, b))
    }
  }

  const n = line.length
  let i = 0
  while (i < n) {
    const c = line.charCodeAt(i)
    if (c === CH.SPACE || c === CH.TAB) {
      i++
      continue
    }
    if (expectOperand) {
      if (isDigit(c)) {
        let j = i + 1
        while (j < n && isDigit(line.charCodeAt(j))) j++
        values.push(checked(BigInt(line.slice(i, j))))
        i = j
        expectOperand = false
        continue
      }
      if (c === CH.MINUS) ops.push(NEG_MARK)
      else if (c === CH.LPAREN) ops.push(LPAREN_MARK)
      else fail()
      i++
      continue
    }
    if (c === CH.RPAREN) {
      while (ops.length > 0 && ops[ops.length - 1] !== LPAREN_MARK) reduceTop()
      if (ops.length === 0) fail()
      ops.pop()
    } else {
      const prec = binaryPrec(c) ?? fail()
      while (ops.length > 0 && precOf(ops[ops.length - 1]) >= prec) reduceTop()
      ops.push(c as BinaryOp)
      expectOperand = true
    }
    i++
  }

  if (expectOperand) fail()
  while (ops.length > 0) reduceTop()
  if (values.length !== 1) fail()
  return values[0]
}

function main(): void {
  const lines = readFileSync(0, 'latin1').split('\n')
  if (lines[lines.length - 1] === '') lines.pop()
  const out: string[] = []
  for (const line of lines) {
    if (/^[ \t]*$/.test(line)) continue
    try {
      out.push(String(evaluate(line)))
    } catch (err) {
      if (!(err instanceof CalcError)) throw err
      out.push('error')
    }
  }
  if (out.length > 0) process.stdout.write(out.join('\n') + '\n')
}

main()
