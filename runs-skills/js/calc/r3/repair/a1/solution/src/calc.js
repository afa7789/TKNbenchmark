// 64-bit signed integer expression evaluator.
//
// Uses an explicit-stack (shunting-yard) parser rather than recursive descent so
// arbitrarily deep nesting cannot overflow the call stack.

export class CalcError extends Error {
  name = 'CalcError';
}

const INT64_MIN = -(2n ** 63n);
const INT64_MAX = 2n ** 63n - 1n;

const CH_SPACE = 0x20;
const CH_TAB = 0x09;
const CH_0 = 0x30;
const CH_9 = 0x39;

const NEG = 'neg';
const LPAREN = '(';

/** Binding power of each operator on the operator stack. */
const PRECEDENCE = { '+': 1, '-': 1, '*': 2, '/': 2, '%': 2, [NEG]: 3 };

const fail = () => {
  throw new CalcError('error');
};

/** @param {bigint} v */
const checked = (v) => (v < INT64_MIN || v > INT64_MAX ? fail() : v);

/**
 * @param {string} op
 * @param {bigint} a
 * @param {bigint} b
 */
function applyBinary(op, a, b) {
  switch (op) {
    case '+':
      return checked(a + b);
    case '-':
      return checked(a - b);
    case '*':
      return checked(a * b);
    case '/':
      return b === 0n ? fail() : checked(a / b);
    case '%':
      // The remainder always fits; INT64_MIN % -1 is 0.
      return b === 0n ? fail() : a % b;
    default:
      throw new Error(`unknown operator ${op}`);
  }
}

/**
 * Pops one operator off `ops` and applies it to the operand stack.
 * @param {string[]} ops
 * @param {bigint[]} values
 */
function reduce(ops, values) {
  const op = ops.pop();
  if (op === NEG) {
    values.push(checked(-values.pop()));
    return;
  }
  const b = values.pop();
  const a = values.pop();
  values.push(applyBinary(op, a, b));
}

/**
 * Evaluates one expression.
 * @param {string} src
 * @returns {bigint}
 * @throws {CalcError} on syntax error, division by zero or overflow.
 */
export function evaluate(src) {
  /** @type {bigint[]} */
  const values = [];
  /** @type {string[]} */
  const ops = [];
  let expectOperand = true;
  const n = src.length;
  let i = 0;

  while (i < n) {
    const c = src.charCodeAt(i);
    if (c === CH_SPACE || c === CH_TAB) {
      i++;
      continue;
    }

    if (expectOperand) {
      if (c >= CH_0 && c <= CH_9) {
        const start = i;
        while (i < n && src.charCodeAt(i) >= CH_0 && src.charCodeAt(i) <= CH_9) i++;
        values.push(checked(BigInt(src.slice(start, i))));
        expectOperand = false;
        continue;
      }
      const ch = src[i++];
      if (ch === '-') ops.push(NEG);
      else if (ch === '(') ops.push(LPAREN);
      else fail();
      continue;
    }

    const ch = src[i++];
    if (ch === ')') {
      while (ops.length > 0 && ops.at(-1) !== LPAREN) reduce(ops, values);
      if (ops.pop() !== LPAREN) fail();
    } else if (Object.hasOwn(PRECEDENCE, ch)) {
      const prec = PRECEDENCE[ch];
      while (ops.length > 0 && ops.at(-1) !== LPAREN && PRECEDENCE[ops.at(-1)] >= prec) {
        reduce(ops, values);
      }
      ops.push(ch);
      expectOperand = true;
    } else {
      fail();
    }
  }

  if (expectOperand) fail();
  while (ops.length > 0) {
    if (ops.at(-1) === LPAREN) fail();
    reduce(ops, values);
  }
  return values[0];
}

/** True when the line is empty or holds only spaces/tabs. */
export const isBlank = (line) => /^[ \t]*$/.test(line);

/**
 * Evaluates one input line, returning the text to print or `null` for blank lines.
 * @param {string} line
 * @returns {string | null}
 */
export function evaluateLine(line) {
  if (isBlank(line)) return null;
  try {
    return evaluate(line).toString();
  } catch (err) {
    if (err instanceof CalcError) return 'error';
    throw err;
  }
}
