import { CalcError } from './calc-error.ts'

/**
 * Evaluator for signed 64-bit integer expressions.
 *
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *   NUMBER  := [0-9]+
 *
 * Spaces and tabs are permitted between tokens. All arithmetic is overflow-checked.
 *
 * The grammar is parsed with an operator-precedence (shunting-yard) algorithm over
 * explicit stacks rather than recursive descent, so arbitrarily deep nesting cannot
 * exhaust the call stack.
 */

const INT64_MIN = -(1n << 63n)
const INT64_MAX = (1n << 63n) - 1n

type BinaryOp = '+' | '-' | '*' | '/' | '%'
type StackOp = BinaryOp | 'neg' | '('

const PRECEDENCE: Readonly<Record<StackOp, number>> = {
  '(': 0,
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
}

const CH_TAB = 0x09
const CH_SPACE = 0x20
const CH_LPAREN = 0x28
const CH_RPAREN = 0x29
const CH_0 = 0x30
const CH_9 = 0x39

const isDigit = (c: number): boolean => c >= CH_0 && c <= CH_9
const isBlankChar = (c: number): boolean => c === CH_SPACE || c === CH_TAB

function checked(value: bigint): bigint {
  if (value < INT64_MIN || value > INT64_MAX) throw new CalcError('overflow')
  return value
}

/** Applies a binary operator with exact 64-bit semantics. */
function applyBinary(op: BinaryOp, left: bigint, right: bigint): bigint {
  switch (op) {
    case '+':
      return checked(left + right)
    case '-':
      return checked(left - right)
    case '*':
      return checked(left * right)
    case '/':
      if (right === 0n) throw new CalcError('division by zero')
      // BigInt division truncates toward zero; only MIN / -1 can leave the range.
      return checked(left / right)
    case '%':
      if (right === 0n) throw new CalcError('division by zero')
      // BigInt remainder takes the sign of the dividend; MIN % -1 is 0.
      return left % right
  }
}

function binaryOpFor(c: number): BinaryOp | undefined {
  switch (c) {
    case 0x2b:
      return '+'
    case 0x2d:
      return '-'
    case 0x2a:
      return '*'
    case 0x2f:
      return '/'
    case 0x25:
      return '%'
    default:
      return undefined
  }
}

class Evaluation {
  private readonly values: bigint[] = []
  private readonly ops: StackOp[] = []

  /** Pops and applies the topmost operator (never '('). */
  private reduceOnce(): void {
    const op = this.ops.pop()
    if (op === 'neg') {
      const operand = this.values.pop()!
      if (operand === INT64_MIN) throw new CalcError('overflow in negation')
      this.values.push(-operand)
    } else if (op !== undefined && op !== '(') {
      const right = this.values.pop()!
      const left = this.values.pop()!
      this.values.push(applyBinary(op, left, right))
    } else {
      throw new Error('internal error: invalid reduction')
    }
  }

  /** Applies stacked operators that bind at least as tightly as `minPrecedence`. */
  private reduceWhile(minPrecedence: number): void {
    const { ops } = this
    while (ops.length > 0 && PRECEDENCE[ops[ops.length - 1]!] >= minPrecedence) {
      this.reduceOnce()
    }
  }

  run(src: string): bigint {
    const { values, ops } = this
    const length = src.length
    let pos = 0
    let expectOperand = true

    while (true) {
      while (pos < length && isBlankChar(src.charCodeAt(pos))) pos++
      if (pos === length) break
      const c = src.charCodeAt(pos)

      if (expectOperand) {
        if (c === 0x2d) {
          ops.push('neg')
          pos++
        } else if (c === CH_LPAREN) {
          ops.push('(')
          pos++
        } else if (isDigit(c)) {
          const start = pos
          do pos++
          while (pos < length && isDigit(src.charCodeAt(pos)))
          values.push(checked(BigInt(src.slice(start, pos))))
          expectOperand = false
        } else {
          throw new CalcError(`expected operand at ${pos}`)
        }
        continue
      }

      if (c === CH_RPAREN) {
        this.reduceWhile(1)
        if (ops.pop() !== '(') throw new CalcError(`unbalanced ')' at ${pos}`)
        pos++
        continue
      }

      const op = binaryOpFor(c)
      if (op === undefined) throw new CalcError(`unexpected character at ${pos}`)
      // All binary operators are left-associative.
      this.reduceWhile(PRECEDENCE[op])
      ops.push(op)
      pos++
      expectOperand = true
    }

    if (expectOperand) throw new CalcError('expected operand at end of input')
    this.reduceWhile(1)
    if (ops.length > 0) throw new CalcError("expected ')' at end of input")
    return values[0]!
  }
}

/** Evaluates a complete expression, throwing {@link CalcError} on any error. */
export function evaluate(expression: string): bigint {
  return new Evaluation().run(expression)
}

/** Whether a line is empty or consists only of spaces and tabs. */
export function isBlank(line: string): boolean {
  for (let i = 0; i < line.length; i++) {
    if (!isBlankChar(line.charCodeAt(i))) return false
  }
  return true
}
