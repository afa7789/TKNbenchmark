/**
 * 64-bit signed integer expression evaluator.
 *
 * Grammar:
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *
 * Parsing uses an explicit operator stack (operator precedence parsing)
 * rather than recursion, so arbitrarily deep nesting cannot overflow the
 * call stack.
 */

const INT64_MIN = -(2n ** 63n);
const INT64_MAX = 2n ** 63n - 1n;

/** Raised for any syntax, division-by-zero or overflow failure. */
export class CalcError extends Error {
  readonly reason: 'syntax' | 'division-by-zero' | 'overflow';

  constructor(reason: CalcError['reason']) {
    super(`calc error: ${reason}`);
    this.name = 'CalcError';
    this.reason = reason;
  }
}

type BinaryOp = '+' | '-' | '*' | '/' | '%';
/** Entries on the operator stack: binary operators, unary negation, or an open parenthesis. */
type StackOp = BinaryOp | 'neg' | '(';

const PRECEDENCE: Record<Exclude<StackOp, '('>, number> = {
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
};

const CH_0 = 0x30;
const CH_9 = 0x39;
const CH_SPACE = 0x20;
const CH_TAB = 0x09;

function checked(value: bigint): bigint {
  if (value < INT64_MIN || value > INT64_MAX) throw new CalcError('overflow');
  return value;
}

function applyBinary(op: BinaryOp, a: bigint, b: bigint): bigint {
  switch (op) {
    case '+':
      return checked(a + b);
    case '-':
      return checked(a - b);
    case '*':
      return checked(a * b);
    case '/':
      if (b === 0n) throw new CalcError('division-by-zero');
      // BigInt division truncates toward zero; MIN / -1 is caught by the range check.
      return checked(a / b);
    case '%':
      if (b === 0n) throw new CalcError('division-by-zero');
      // BigInt remainder follows the dividend's sign; MIN % -1 is 0.
      return a % b;
  }
}

function parseLiteral(digits: string): bigint {
  const value = BigInt(digits);
  if (value > INT64_MAX) throw new CalcError('overflow');
  return value;
}

const isBlank = (c: number): boolean => c === CH_SPACE || c === CH_TAB;
const isDigit = (c: number): boolean => c >= CH_0 && c <= CH_9;

/** Evaluates one expression, throwing CalcError on failure. */
export function evaluate(line: string): bigint {
  const values: bigint[] = [];
  const ops: StackOp[] = [];

  const reduceTop = (): void => {
    const op = ops.pop();
    if (op === 'neg') {
      values.push(checked(-values.pop()!));
    } else if (op !== undefined && op !== '(') {
      const b = values.pop()!;
      const a = values.pop()!;
      values.push(applyBinary(op, a, b));
    }
  };

  // Reduces stacked operators that bind at least as tightly as `minPrecedence`.
  const reduceWhile = (minPrecedence: number): void => {
    while (ops.length > 0) {
      const top = ops[ops.length - 1];
      if (top === '(' || PRECEDENCE[top] < minPrecedence) return;
      reduceTop();
    }
  };

  let expectOperand = true;
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
        let end = i + 1;
        while (end < n && isDigit(line.charCodeAt(end))) end++;
        values.push(parseLiteral(line.slice(i, end)));
        i = end;
        expectOperand = false;
        continue;
      }
      if (ch === '-') ops.push('neg');
      else if (ch === '(') ops.push('(');
      else throw new CalcError('syntax');
      i++;
      continue;
    }

    switch (ch) {
      case '+':
      case '-':
      case '*':
      case '/':
      case '%':
        reduceWhile(PRECEDENCE[ch]);
        ops.push(ch);
        expectOperand = true;
        break;
      case ')':
        reduceWhile(0);
        if (ops.pop() !== '(') throw new CalcError('syntax');
        break;
      default:
        throw new CalcError('syntax');
    }
    i++;
  }

  if (expectOperand) throw new CalcError('syntax');
  reduceWhile(0);
  if (ops.length > 0) throw new CalcError('syntax');
  return values[0];
}

function isBlankLine(line: string): boolean {
  for (let i = 0; i < line.length; i++) {
    if (!isBlank(line.charCodeAt(i))) return false;
  }
  return true;
}

/** Returns the output for one input line, or null for a blank line. */
export function lineResult(line: string): string | null {
  if (isBlankLine(line)) return null;
  try {
    return evaluate(line).toString();
  } catch (err) {
    if (err instanceof CalcError) return 'error';
    throw err;
  }
}
