/** Signed 64-bit integer expression evaluator. */

const INT64_MIN = -(2n ** 63n);
const INT64_MAX = 2n ** 63n - 1n;

/** Thrown for any syntax, division-by-zero or overflow error. */
export class CalcError extends Error {
  override name = 'CalcError';
}

type BinaryOp = '+' | '-' | '*' | '/' | '%';
type StackOp = BinaryOp | 'neg' | '(';

const PRECEDENCE: Readonly<Record<Exclude<StackOp, '('>, number>> = {
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
};

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
      if (b === 0n) throw new CalcError('division by zero');
      return checked(a / b); // BigInt division truncates toward zero
    case '%':
      if (b === 0n) throw new CalcError('division by zero');
      return a % b; // sign follows the dividend; never overflows
  }
}

function isDigit(code: number): boolean {
  return code >= 48 && code <= 57;
}

/**
 * Evaluates one expression line. Returns `undefined` for a blank line.
 * Uses an iterative operator-precedence parser so deeply nested input
 * cannot exhaust the call stack.
 */
export function evaluate(line: string): bigint | undefined {
  const values: bigint[] = [];
  const ops: StackOp[] = [];
  let expectOperand = true;
  let sawToken = false;

  const reduce = (): void => {
    const op = ops.pop();
    if (op === undefined || op === '(') throw new CalcError('syntax');
    if (op === 'neg') {
      const a = values.pop();
      if (a === undefined) throw new CalcError('syntax');
      values.push(checked(-a));
      return;
    }
    const b = values.pop();
    const a = values.pop();
    if (a === undefined || b === undefined) throw new CalcError('syntax');
    values.push(applyBinary(op, a, b));
  };

  const len = line.length;
  let i = 0;
  while (i < len) {
    const ch = line[i] as string;
    if (ch === ' ' || ch === '\t') {
      i++;
      continue;
    }
    sawToken = true;

    if (expectOperand) {
      if (isDigit(line.charCodeAt(i))) {
        const start = i;
        while (i < len && isDigit(line.charCodeAt(i))) i++;
        const literal = BigInt(line.slice(start, i));
        if (literal > INT64_MAX) throw new CalcError('literal overflow');
        values.push(literal);
        expectOperand = false;
        continue;
      }
      if (ch === '-') ops.push('neg');
      else if (ch === '(') ops.push('(');
      else throw new CalcError('syntax');
      i++;
      continue;
    }

    if (ch === ')') {
      while (ops.length > 0 && ops[ops.length - 1] !== '(') reduce();
      if (ops.pop() !== '(') throw new CalcError('unbalanced parentheses');
    } else if (ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '%') {
      const prec = PRECEDENCE[ch];
      for (;;) {
        const top = ops[ops.length - 1];
        if (top === undefined || top === '(' || PRECEDENCE[top] < prec) break;
        reduce();
      }
      ops.push(ch);
      expectOperand = true;
    } else {
      throw new CalcError('syntax');
    }
    i++;
  }

  if (!sawToken) return undefined;
  if (expectOperand) throw new CalcError('missing operand');
  while (ops.length > 0) reduce();
  if (values.length !== 1) throw new CalcError('syntax');
  return values[0];
}

/** Formats the result for one input line, or `undefined` if it prints nothing. */
export function evaluateLine(line: string): string | undefined {
  try {
    return evaluate(line)?.toString();
  } catch (e) {
    if (e instanceof CalcError) return 'error';
    throw e;
  }
}
