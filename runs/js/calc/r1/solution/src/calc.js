'use strict';

const INT64_MIN = -(2n ** 63n);
const INT64_MAX = 2n ** 63n - 1n;

class CalcError extends Error {}

const PRECEDENCE = { '+': 1, '-': 1, '*': 2, '/': 2, '%': 2, neg: 3 };

function checked(value) {
  if (value < INT64_MIN || value > INT64_MAX) throw new CalcError('overflow');
  return value;
}

function applyBinary(op, a, b) {
  switch (op) {
    case '+': return checked(a + b);
    case '-': return checked(a - b);
    case '*': return checked(a * b);
    case '/':
      if (b === 0n) throw new CalcError('division by zero');
      return checked(a / b); // BigInt division truncates toward zero
    case '%':
      if (b === 0n) throw new CalcError('division by zero');
      return a % b; // sign follows the dividend; never overflows
    default:
      throw new Error(`unknown operator ${op}`);
  }
}

const isDigit = (c) => c >= 48 && c <= 57; // '0'..'9'
const isBlank = (c) => c === 32 || c === 9; // ' ' or '\t'

/**
 * Evaluates one expression using an operator-precedence (shunting-yard)
 * parser, so deeply nested input cannot exhaust the call stack.
 * Returns a BigInt, or throws CalcError.
 */
function evaluate(line) {
  const values = [];
  const ops = [];
  let expectOperand = true;

  const reduce = () => {
    const op = ops.pop();
    if (op === 'neg') {
      values.push(checked(-values.pop()));
    } else {
      const b = values.pop();
      const a = values.pop();
      values.push(applyBinary(op, a, b));
    }
  };

  const n = line.length;
  let i = 0;
  while (i < n) {
    const c = line.charCodeAt(i);
    if (isBlank(c)) {
      i++;
      continue;
    }
    const ch = line[i];
    if (expectOperand) {
      if (isDigit(c)) {
        let j = i + 1;
        while (j < n && isDigit(line.charCodeAt(j))) j++;
        values.push(checked(BigInt(line.slice(i, j))));
        i = j;
        expectOperand = false;
        continue;
      }
      if (ch === '-') ops.push('neg');
      else if (ch === '(') ops.push('(');
      else throw new CalcError('syntax error');
    } else if (ch in PRECEDENCE) {
      const prec = PRECEDENCE[ch];
      while (ops.length > 0 && ops[ops.length - 1] !== '(' && PRECEDENCE[ops[ops.length - 1]] >= prec) {
        reduce();
      }
      ops.push(ch);
      expectOperand = true;
    } else if (ch === ')') {
      while (ops.length > 0 && ops[ops.length - 1] !== '(') reduce();
      if (ops.length === 0) throw new CalcError('unbalanced parentheses');
      ops.pop();
    } else {
      throw new CalcError('syntax error');
    }
    i++;
  }

  if (expectOperand) throw new CalcError('missing operand');
  while (ops.length > 0) {
    if (ops[ops.length - 1] === '(') throw new CalcError('unbalanced parentheses');
    reduce();
  }
  return values[0];
}

/** Returns the output line for one input line, or null for blank lines. */
function processLine(line) {
  if (/^[ \t]*$/.test(line)) return null;
  try {
    return evaluate(line).toString();
  } catch (err) {
    if (err instanceof CalcError) return 'error';
    throw err;
  }
}

module.exports = { evaluate, processLine, CalcError };
