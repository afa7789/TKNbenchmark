// 64-bit signed integer expression evaluator.
//
// Grammar:
//   expr    := term    (('+' | '-') term)*
//   term    := unary   (('*' | '/' | '%') unary)*
//   unary   := '-' unary | primary
//   primary := NUMBER | '(' expr ')'
//
// Parsing uses an operator-precedence (shunting-yard) algorithm with explicit
// stacks, so arbitrarily deep nesting cannot overflow the call stack.

export const INT64_MIN = -(2n ** 63n);
export const INT64_MAX = 2n ** 63n - 1n;

/** Thrown for any syntax, division-by-zero or overflow error. */
export class CalcError extends Error {
  name = 'CalcError';
}

const NEG = 'neg';
const LPAREN = '(';

const PRECEDENCE = { '+': 1, '-': 1, '*': 2, '/': 2, '%': 2, [NEG]: 3 };

const CH_SPACE = 0x20;
const CH_TAB = 0x09;
const CH_0 = 0x30;
const CH_9 = 0x39;

const isBlank = (c) => c === CH_SPACE || c === CH_TAB;
const isDigit = (c) => c >= CH_0 && c <= CH_9;

function checked(value) {
  if (value < INT64_MIN || value > INT64_MAX) throw new CalcError('overflow');
  return value;
}

function applyBinary(op, a, b) {
  switch (op) {
    case '+':
      return checked(a + b);
    case '-':
      return checked(a - b);
    case '*':
      return checked(a * b);
    case '/':
      if (b === 0n) throw new CalcError('division by zero');
      return checked(a / b); // BigInt division truncates toward zero
    case '%':
      if (b === 0n) throw new CalcError('division by zero');
      return a % b; // sign follows the dividend; |a % b| < |b| never overflows
    default:
      throw new Error(`unknown operator ${op}`);
  }
}

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

/** Returns true if the line holds only spaces and tabs. */
export function isBlankLine(line) {
  for (let i = 0; i < line.length; i++) {
    if (!isBlank(line.charCodeAt(i))) return false;
  }
  return true;
}

/**
 * Evaluates one expression and returns its value as a BigInt.
 * @param {string} source
 * @returns {bigint}
 * @throws {CalcError}
 */
export function evaluate(source) {
  const ops = [];
  const values = [];
  let expectOperand = true;
  const n = source.length;
  let i = 0;

  while (i < n) {
    const c = source.charCodeAt(i);
    if (isBlank(c)) {
      i++;
      continue;
    }

    if (isDigit(c)) {
      if (!expectOperand) throw new CalcError('unexpected number');
      const start = i;
      while (i < n && isDigit(source.charCodeAt(i))) i++;
      values.push(checked(BigInt(source.slice(start, i))));
      expectOperand = false;
      continue;
    }

    const ch = source[i++];
    if (expectOperand) {
      if (ch === '-') ops.push(NEG);
      else if (ch === '(') ops.push(LPAREN);
      else throw new CalcError(`unexpected '${ch}'`);
      continue;
    }

    if (ch === ')') {
      while (ops.length > 0 && ops.at(-1) !== LPAREN) reduce(ops, values);
      if (ops.length === 0) throw new CalcError("unbalanced ')'");
      ops.pop();
      continue;
    }

    const prec = PRECEDENCE[ch];
    if (prec === undefined || ch === NEG) throw new CalcError(`unexpected '${ch}'`);
    // Left-associative: reduce everything of equal or higher precedence.
    while (ops.length > 0 && ops.at(-1) !== LPAREN && PRECEDENCE[ops.at(-1)] >= prec) {
      reduce(ops, values);
    }
    ops.push(ch);
    expectOperand = true;
  }

  if (expectOperand) throw new CalcError('missing operand');
  while (ops.length > 0) {
    if (ops.at(-1) === LPAREN) throw new CalcError("unbalanced '('");
    reduce(ops, values);
  }
  return values[0];
}

/**
 * Evaluates one input line, returning the text to print or null for blank lines.
 * @param {string} line
 * @returns {string | null}
 */
export function evaluateLine(line) {
  if (isBlankLine(line)) return null;
  try {
    return evaluate(line).toString();
  } catch (err) {
    if (err instanceof CalcError) return 'error';
    throw err;
  }
}
