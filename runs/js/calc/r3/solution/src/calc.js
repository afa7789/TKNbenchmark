'use strict'
// 64-bit signed integer expression evaluator. Reads expressions from stdin,
// one per line, and prints each value or `error`.
//
// The parser is an iterative operator-precedence (shunting-yard) evaluator so
// that arbitrarily deep nesting cannot overflow the call stack.

const { readFileSync } = require('node:fs')

const INT64_MIN = -(2n ** 63n)
const INT64_MAX = 2n ** 63n - 1n

class CalcError extends Error {}

const fail = () => {
  throw new CalcError()
}

const checked = (v) => (v < INT64_MIN || v > INT64_MAX ? fail() : v)

// Operator stack markers.
const LPAREN = 0
const NEG = 1
const BINARY_PREC = { 43: 1, 45: 1, 42: 2, 47: 2, 37: 2 } // + - * / %
const NEG_PREC = 3

function applyBinary(op, a, b) {
  switch (op) {
    case 43: return checked(a + b)
    case 45: return checked(a - b)
    case 42: return checked(a * b)
    case 47: return b === 0n ? fail() : checked(a / b)
    case 37: return b === 0n ? fail() : a % b
  }
  return fail()
}

const precOf = (op) => (op === NEG ? NEG_PREC : op === LPAREN ? 0 : BINARY_PREC[op])

/** Evaluate one expression line; returns a BigInt or throws CalcError. */
function evaluate(line) {
  const values = []
  const ops = []
  let expectOperand = true

  const reduceTop = () => {
    const op = ops.pop()
    if (op === NEG) {
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
    if (c === 32 || c === 9) {
      i++
      continue
    }
    if (expectOperand) {
      if (c >= 48 && c <= 57) {
        let j = i + 1
        while (j < n && line.charCodeAt(j) >= 48 && line.charCodeAt(j) <= 57) j++
        values.push(checked(BigInt(line.slice(i, j))))
        i = j
        expectOperand = false
        continue
      }
      if (c === 45) ops.push(NEG)
      else if (c === 40) ops.push(LPAREN)
      else fail()
      i++
      continue
    }
    if (c === 41) {
      while (ops.length > 0 && ops[ops.length - 1] !== LPAREN) reduceTop()
      if (ops.length === 0) fail()
      ops.pop()
    } else if (c in BINARY_PREC) {
      const prec = BINARY_PREC[c]
      while (ops.length > 0 && precOf(ops[ops.length - 1]) >= prec) reduceTop()
      ops.push(c)
      expectOperand = true
    } else {
      fail()
    }
    i++
  }

  if (expectOperand) fail()
  while (ops.length > 0) {
    if (ops[ops.length - 1] === LPAREN) fail()
    reduceTop()
  }
  return values[0]
}

function main() {
  const input = readFileSync(0, 'latin1')
  const lines = input.split('\n')
  if (lines[lines.length - 1] === '') lines.pop()
  const out = []
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
