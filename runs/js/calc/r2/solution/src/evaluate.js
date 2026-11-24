'use strict'

const INT64_MIN = -(2n ** 63n)
const INT64_MAX = 2n ** 63n - 1n

/** Thrown for any condition that makes a line evaluate to `error`. */
class EvalError extends Error {}

const fail = (message) => {
  throw new EvalError(message)
}

const checked = (value) => (value < INT64_MIN || value > INT64_MAX ? fail('overflow') : value)

const CH_TAB = 9
const CH_SPACE = 32
const CH_LPAREN = 40
const CH_RPAREN = 41
const CH_STAR = 42
const CH_PLUS = 43
const CH_MINUS = 45
const CH_SLASH = 47
const CH_PERCENT = 37
const CH_0 = 48
const CH_9 = 57

// Operator stack entries. Binary operators carry their own character code.
const LPAREN = 0
const NEGATE = 1

const precedence = (op) => {
  switch (op) {
    case CH_PLUS:
    case CH_MINUS:
      return 1
    case CH_STAR:
    case CH_SLASH:
    case CH_PERCENT:
      return 2
    case NEGATE:
      return 3
    default:
      return 0
  }
}

function applyBinary(op, a, b) {
  switch (op) {
    case CH_PLUS:
      return checked(a + b)
    case CH_MINUS:
      return checked(a - b)
    case CH_STAR:
      return checked(a * b)
    case CH_SLASH:
      if (b === 0n) fail('division by zero')
      return checked(a / b) // BigInt division truncates toward zero
    case CH_PERCENT:
      if (b === 0n) fail('division by zero')
      return a % b // sign follows the dividend; never overflows
    default:
      throw new Error(`unknown operator ${op}`)
  }
}

/**
 * Evaluate one expression as signed 64-bit integer arithmetic.
 * Uses an iterative operator-precedence parser so arbitrarily deep nesting
 * cannot exhaust the call stack.
 *
 * @param {string} line
 * @returns {bigint | null} the value, or null when the line is blank
 * @throws {EvalError} on syntax error, division by zero or overflow
 */
function evaluate(line) {
  const values = []
  const ops = []
  let expectOperand = true
  let sawToken = false

  const reduceTop = () => {
    const op = ops.pop()
    if (op === NEGATE) {
      values.push(checked(-values.pop()))
    } else {
      const b = values.pop()
      const a = values.pop()
      values.push(applyBinary(op, a, b))
    }
  }

  const n = line.length
  let i = 0
  while (i < n) {
    const c = line.charCodeAt(i)
    if (c === CH_SPACE || c === CH_TAB) {
      i++
      continue
    }
    sawToken = true

    if (expectOperand) {
      if (c >= CH_0 && c <= CH_9) {
        const start = i
        while (i < n && line.charCodeAt(i) >= CH_0 && line.charCodeAt(i) <= CH_9) i++
        values.push(checked(BigInt(line.slice(start, i))))
        expectOperand = false
        continue
      }
      if (c === CH_MINUS) ops.push(NEGATE)
      else if (c === CH_LPAREN) ops.push(LPAREN)
      else fail('expected operand')
      i++
      continue
    }

    switch (c) {
      case CH_PLUS:
      case CH_MINUS:
      case CH_STAR:
      case CH_SLASH:
      case CH_PERCENT: {
        // All binary operators are left-associative.
        const p = precedence(c)
        while (ops.length > 0 && precedence(ops[ops.length - 1]) >= p) reduceTop()
        ops.push(c)
        expectOperand = true
        break
      }
      case CH_RPAREN:
        while (ops.length > 0 && ops[ops.length - 1] !== LPAREN) reduceTop()
        if (ops.length === 0) fail('unbalanced parenthesis')
        ops.pop()
        break
      default:
        fail('unexpected character')
    }
    i++
  }

  if (!sawToken) return null
  if (expectOperand) fail('missing operand')
  while (ops.length > 0) {
    if (ops[ops.length - 1] === LPAREN) fail('unbalanced parenthesis')
    reduceTop()
  }
  return values[0]
}

module.exports = { evaluate, EvalError }
