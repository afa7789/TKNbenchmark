import { readFileSync, writeSync } from 'node:fs'

const INT64_MIN = -(1n << 63n)
const INT64_MAX = (1n << 63n) - 1n

/** Raised for any condition that makes a line evaluate to `error`. */
class CalcError extends Error {}

type BinaryOp = '+' | '-' | '*' | '/' | '%'
type StackOp = BinaryOp | 'neg' | '('

const PRECEDENCE: Record<StackOp, number> = {
  '(': 0,
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
}

function checked(value: bigint): bigint {
  if (value < INT64_MIN || value > INT64_MAX) throw new CalcError('overflow')
  return value
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
      if (b === 0n) throw new CalcError('division by zero')
      return checked(a / b) // BigInt division truncates toward zero
    case '%':
      if (b === 0n) throw new CalcError('division by zero')
      return a % b // sign follows the dividend; never overflows
  }
}

const isDigit = (c: number): boolean => c >= 48 && c <= 57 // '0'..'9'
const isBlank = (c: number): boolean => c === 32 || c === 9 // ' ' or '\t'

/**
 * Evaluates one expression using an operator-precedence (shunting-yard)
 * parser with explicit stacks, so deeply nested input cannot overflow the
 * call stack.
 */
function evaluate(line: string): bigint {
  const values: bigint[] = []
  const ops: StackOp[] = []
  let expectOperand = true

  const reduceTop = (): void => {
    const op = ops.pop()
    if (op === undefined || op === '(') throw new CalcError('internal')
    if (op === 'neg') {
      values.push(checked(-values.pop()!))
    } else {
      const b = values.pop()!
      const a = values.pop()!
      values.push(applyBinary(op, a, b))
    }
  }

  const n = line.length
  let i = 0
  while (i < n) {
    const c = line.charCodeAt(i)
    if (isBlank(c)) {
      i++
      continue
    }
    const ch = line[i]

    if (expectOperand) {
      if (isDigit(c)) {
        let j = i + 1
        while (j < n && isDigit(line.charCodeAt(j))) j++
        values.push(checked(BigInt(line.slice(i, j))))
        i = j
        expectOperand = false
        continue
      }
      if (ch === '-') ops.push('neg')
      else if (ch === '(') ops.push('(')
      else throw new CalcError('syntax')
      i++
      continue
    }

    if (ch === ')') {
      while (ops.length > 0 && ops[ops.length - 1] !== '(') reduceTop()
      if (ops.length === 0) throw new CalcError('unbalanced')
      ops.pop()
    } else if (ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '%') {
      const prec = PRECEDENCE[ch]
      while (ops.length > 0 && PRECEDENCE[ops[ops.length - 1]] >= prec) reduceTop()
      ops.push(ch)
      expectOperand = true
    } else {
      throw new CalcError('syntax')
    }
    i++
  }

  if (expectOperand) throw new CalcError('missing operand')
  while (ops.length > 0) {
    if (ops[ops.length - 1] === '(') throw new CalcError('unbalanced')
    reduceTop()
  }
  return values[0]
}

function isBlankLine(line: string): boolean {
  for (let i = 0; i < line.length; i++) {
    if (!isBlank(line.charCodeAt(i))) return false
  }
  return true
}

function main(): void {
  const input = readFileSync(0, 'latin1')
  const lines = input.split('\n')
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop()

  const out: string[] = []
  for (const line of lines) {
    if (isBlankLine(line)) continue
    try {
      out.push(evaluate(line).toString())
    } catch (err) {
      if (!(err instanceof CalcError)) throw err
      out.push('error')
    }
  }

  if (out.length > 0) {
    const data = Buffer.from(out.join('\n') + '\n')
    let offset = 0
    while (offset < data.length) offset += writeSync(1, data, offset)
  }
}

main()
