/**
 * Evaluator for 64-bit signed integer expressions.
 *
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * NUMBER  := [0-9]+
 * ```
 *
 * Parsing uses operator precedence with explicit stacks instead of recursion, so arbitrarily
 * deep nesting cannot exhaust the call stack. Any syntax error, division by zero or 64-bit
 * overflow makes the whole expression fail.
 */

export class EvaluationError extends Error {
  override name = 'EvaluationError'
}

const INT64_MIN = -(1n << 63n)
const INT64_MAX = (1n << 63n) - 1n
const INT64_MAX_DIGITS = INT64_MAX.toString().length

const CH_TAB = 0x09
const CH_SPACE = 0x20
const CH_PERCENT = 0x25
const CH_LPAREN = 0x28
const CH_RPAREN = 0x29
const CH_STAR = 0x2a
const CH_PLUS = 0x2b
const CH_MINUS = 0x2d
const CH_SLASH = 0x2f
const CH_0 = 0x30
const CH_9 = 0x39

/** Entries of the operator stack: an opening parenthesis, a unary negation or a binary operator. */
const Op = {
  Paren: 0,
  Negate: 1,
  Add: 2,
  Subtract: 3,
  Multiply: 4,
  Divide: 5,
  Remainder: 6,
} as const
type Op = (typeof Op)[keyof typeof Op]

export function isBlank(c: number): boolean {
  return c === CH_SPACE || c === CH_TAB
}

function isDigit(c: number): boolean {
  return c >= CH_0 && c <= CH_9
}

function binaryOp(c: number): Op | undefined {
  switch (c) {
    case CH_PLUS:
      return Op.Add
    case CH_MINUS:
      return Op.Subtract
    case CH_STAR:
      return Op.Multiply
    case CH_SLASH:
      return Op.Divide
    case CH_PERCENT:
      return Op.Remainder
    default:
      return undefined
  }
}

function precedence(op: Op): number {
  return op === Op.Add || op === Op.Subtract ? 1 : 2
}

function checked(value: bigint): bigint {
  if (value < INT64_MIN || value > INT64_MAX) throw new EvaluationError('overflow')
  return value
}

function apply(op: Op, left: bigint, right: bigint): bigint {
  switch (op) {
    case Op.Add:
      return checked(left + right)
    case Op.Subtract:
      return checked(left - right)
    case Op.Multiply:
      return checked(left * right)
    case Op.Divide:
      if (right === 0n) throw new EvaluationError('division by zero')
      return checked(left / right)
    case Op.Remainder:
      if (right === 0n) throw new EvaluationError('division by zero')
      return left % right
    default:
      throw new Error(`not a binary operator: ${op}`)
  }
}

/** Evaluates `src[start, end)` (ASCII bytes) as a complete expression. */
export function evaluate(src: Uint8Array, start = 0, end = src.length): bigint {
  const values: bigint[] = []
  const ops: Op[] = []
  let pos = start

  const skipBlanks = (): void => {
    while (pos < end && isBlank(src[pos]!)) pos++
  }

  /** Pops and applies binary operators while they bind at least as tightly as `minPrecedence`. */
  const reduce = (minPrecedence: number): void => {
    while (ops.length > 0) {
      const top = ops[ops.length - 1]!
      if (top === Op.Paren || precedence(top) < minPrecedence) return
      ops.pop()
      const right = values.pop()!
      const left = values.pop()!
      values.push(apply(top, left, right))
    }
  }

  /** Pushes a completed operand, applying any negations that immediately precede it. */
  const pushOperand = (value: bigint): void => {
    while (ops.length > 0 && ops[ops.length - 1] === Op.Negate) {
      ops.pop()
      value = checked(-value)
    }
    values.push(value)
  }

  const number = (): bigint => {
    const digitsStart = pos
    while (pos < end && isDigit(src[pos]!)) pos++
    let first = digitsStart
    while (first < pos - 1 && src[first] === CH_0) first++
    if (pos - first > INT64_MAX_DIGITS) throw new EvaluationError('literal out of range')
    const value = BigInt(String.fromCharCode(...src.subarray(first, pos)))
    if (value > INT64_MAX) throw new EvaluationError('literal out of range')
    return value
  }

  for (;;) {
    // Expecting an operand: any number of '-' and '(' followed by a NUMBER.
    for (;;) {
      skipBlanks()
      const c = pos < end ? src[pos]! : -1
      if (c === CH_MINUS) {
        ops.push(Op.Negate)
        pos++
      } else if (c === CH_LPAREN) {
        ops.push(Op.Paren)
        pos++
      } else if (isDigit(c)) {
        pushOperand(number())
        break
      } else {
        throw new EvaluationError('expected operand')
      }
    }

    // After an operand: any number of ')', then a binary operator or the end of input.
    for (;;) {
      skipBlanks()
      if (pos >= end) {
        reduce(0)
        if (ops.length > 0) throw new EvaluationError("expected ')'")
        return values.pop()!
      }
      const c = src[pos++]!
      if (c === CH_RPAREN) {
        reduce(0)
        if (ops.pop() !== Op.Paren) throw new EvaluationError("unexpected ')'")
        pushOperand(values.pop()!)
        continue
      }
      const op = binaryOp(c)
      if (op === undefined) throw new EvaluationError('unexpected character')
      reduce(precedence(op))
      ops.push(op)
      break
    }
  }
}
