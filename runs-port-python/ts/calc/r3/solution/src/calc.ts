/**
 * calc: evaluate 64-bit signed integer expressions, one per input line.
 *
 * Each non-blank line of standard input is parsed and evaluated; its value,
 * or `error`, is written to standard output.
 */

import { readFileSync } from 'node:fs'

const INT64_MIN = -(1n << 63n)
const INT64_MAX = (1n << 63n) - 1n

/** Raised for any syntax, range, or arithmetic error in an expression. */
export class CalcError extends Error {
  override name = 'CalcError'
}

type BinaryOp = '+' | '-' | '*' | '/' | '%'
type StackOp = BinaryOp | 'neg' | '('

/** Binary operator precedence. Unary minus binds tighter than all of these. */
const BINARY_PRECEDENCE: Readonly<Record<BinaryOp, number>> = {
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
}

const isBinaryOp = (ch: string): ch is BinaryOp => Object.hasOwn(BINARY_PRECEDENCE, ch)

const isDigit = (code: number): boolean => code >= 0x30 && code <= 0x39

const isBlank = (code: number): boolean => code === 0x20 || code === 0x09

function checked(value: bigint): bigint {
  if (value < INT64_MIN || value > INT64_MAX) throw new CalcError('overflow')
  return value
}

/** Quotient truncated toward zero (BigInt division already truncates). */
function truncatedQuotient(a: bigint, b: bigint): bigint {
  if (b === 0n) throw new CalcError('division by zero')
  return a / b
}

function applyBinary(op: BinaryOp, a: bigint, b: bigint): bigint {
  switch (op) {
    case '+':
      return checked(a + b)
    case '-':
      return checked(a - b)
    case '*':
      return checked(a * b)
    case '/':
      return checked(truncatedQuotient(a, b))
    case '%':
      // Remainder of truncating division; always representable.
      return a - b * truncatedQuotient(a, b)
  }
}

/**
 * Split a line into tokens: digit runs and single non-blank characters.
 * Unknown characters surface as tokens and are rejected by the parser.
 */
function* tokenize(line: string): Generator<string> {
  const n = line.length
  let i = 0
  while (i < n) {
    const code = line.charCodeAt(i)
    if (isBlank(code)) {
      i++
    } else if (isDigit(code)) {
      const start = i
      while (i < n && isDigit(line.charCodeAt(i))) i++
      yield line.slice(start, i)
    } else {
      yield line[i]!
      i++
    }
  }
}

/**
 * Evaluate one expression, throwing CalcError if it is invalid.
 *
 * Uses an iterative operator-precedence (shunting-yard) parser so deeply
 * nested input cannot exhaust the call stack.
 */
export function evaluate(line: string): bigint {
  const values: bigint[] = []
  const ops: StackOp[] = []

  const reduceTop = (): void => {
    const op = ops.pop()!
    if (op === 'neg') {
      values.push(checked(-values.pop()!))
    } else if (op !== '(') {
      const b = values.pop()!
      const a = values.pop()!
      values.push(applyBinary(op, a, b))
    }
  }

  let expectOperand = true
  for (const token of tokenize(line)) {
    if (expectOperand) {
      if (isDigit(token.charCodeAt(0))) {
        values.push(checked(BigInt(token)))
        expectOperand = false
      } else if (token === '-') {
        ops.push('neg')
      } else if (token === '(') {
        ops.push('(')
      } else {
        throw new CalcError(`unexpected token ${JSON.stringify(token)}`)
      }
    } else if (isBinaryOp(token)) {
      // Left-associative: reduce everything of equal or higher binding
      // (unary minus always qualifies) before pushing this operator.
      const precedence = BINARY_PRECEDENCE[token]
      for (;;) {
        const top = ops.at(-1)
        if (top === undefined || top === '(') break
        if (top !== 'neg' && BINARY_PRECEDENCE[top] < precedence) break
        reduceTop()
      }
      ops.push(token)
      expectOperand = true
    } else if (token === ')') {
      while (ops.length > 0 && ops.at(-1) !== '(') reduceTop()
      if (ops.length === 0) throw new CalcError("unbalanced ')'")
      ops.pop()
    } else {
      throw new CalcError(`unexpected token ${JSON.stringify(token)}`)
    }
  }

  if (expectOperand) throw new CalcError('missing operand')
  while (ops.length > 0) {
    if (ops.at(-1) === '(') throw new CalcError("unbalanced '('")
    reduceTop()
  }
  return values.pop()!
}

const isBlankLine = (line: string): boolean => {
  for (let i = 0; i < line.length; i++) {
    if (!isBlank(line.charCodeAt(i))) return false
  }
  return true
}

/** Yield the output line for each input expression, skipping blanks. */
export function* processLines(lines: Iterable<string>): Generator<string> {
  for (const line of lines) {
    if (isBlankLine(line)) continue
    try {
      yield evaluate(line).toString()
    } catch (err) {
      if (!(err instanceof CalcError)) throw err
      yield 'error'
    }
  }
}

function main(): number {
  // latin1 maps every byte to one character, so arbitrary bytes are
  // accepted and simply rejected as invalid tokens.
  const lines = readFileSync(0).toString('latin1').split('\n')
  if (lines.at(-1) === '') lines.pop()
  const out = Array.from(processLines(lines)).join('\n')
  if (out) process.stdout.write(out + '\n')
  return 0
}

process.exitCode = main()
