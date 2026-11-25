// 64-bit signed integer expression evaluator.
//
// Uses an iterative operator-precedence (shunting-yard) parser so that deeply
// nested input cannot overflow the call stack.

const MIN = -(2n ** 63n);
const MAX = 2n ** 63n - 1n;

/** Thrown for any syntax, division-by-zero or overflow error. */
export class CalcError extends Error {}

const UNARY_MINUS = 'neg';
const LPAREN = '(';
const PRECEDENCE = { '+': 1, '-': 1, '*': 2, '/': 2, '%': 2, [UNARY_MINUS]: 3 };

const isDigit = (code) => code >= 48 && code <= 57;
const isBlank = (ch) => ch === ' ' || ch === '\t';

function checked(value) {
  if (value < MIN || value > MAX) throw new CalcError('overflow');
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

/** Pops the top operator and applies it to the operand stack. */
function reduce(ops, values) {
  const op = ops.pop();
  if (op === UNARY_MINUS) {
    values.push(checked(-values.pop()));
  } else {
    const b = values.pop();
    const a = values.pop();
    values.push(applyBinary(op, a, b));
  }
}

/**
 * Evaluates one expression.
 * @param {string} line
 * @returns {bigint}
 * @throws {CalcError}
 */
export function evaluate(line) {
  const ops = [];
  const values = [];
  let expectOperand = true;
  let i = 0;
  const n = line.length;

  while (i < n) {
    const ch = line[i];
    if (isBlank(ch)) {
      i++;
      continue;
    }

    if (expectOperand) {
      if (isDigit(line.charCodeAt(i))) {
        const start = i;
        while (i < n && isDigit(line.charCodeAt(i))) i++;
        const value = BigInt(line.slice(start, i));
        if (value > MAX) throw new CalcError('literal out of range');
        values.push(value);
        expectOperand = false;
        continue;
      }
      if (ch === '-') ops.push(UNARY_MINUS);
      else if (ch === LPAREN) ops.push(LPAREN);
      else throw new CalcError(`unexpected ${JSON.stringify(ch)}`);
    } else if (ch === ')') {
      while (ops.length > 0 && ops.at(-1) !== LPAREN) reduce(ops, values);
      if (ops.length === 0) throw new CalcError('unbalanced )');
      ops.pop();
    } else if (Object.hasOwn(PRECEDENCE, ch)) {
      const prec = PRECEDENCE[ch];
      while (ops.length > 0 && ops.at(-1) !== LPAREN && PRECEDENCE[ops.at(-1)] >= prec) {
        reduce(ops, values);
      }
      ops.push(ch);
      expectOperand = true;
    } else {
      throw new CalcError(`unexpected ${JSON.stringify(ch)}`);
    }
    i++;
  }

  if (expectOperand) throw new CalcError('missing operand');
  while (ops.length > 0) {
    if (ops.at(-1) === LPAREN) throw new CalcError('unbalanced (');
    reduce(ops, values);
  }
  return values[0];
}

/**
 * Evaluates every line of the input and returns the output lines.
 * Blank lines (only spaces/tabs) produce no output.
 * @param {string} input
 * @returns {string[]}
 */
export function evaluateLines(input) {
  const lines = input.split('\n');
  if (lines.at(-1) === '') lines.pop();
  const out = [];
  for (const line of lines) {
    if (/^[ \t]*$/.test(line)) continue;
    try {
      out.push(String(evaluate(line)));
    } catch (err) {
      if (!(err instanceof CalcError)) throw err;
      out.push('error');
    }
  }
  return out;
}
