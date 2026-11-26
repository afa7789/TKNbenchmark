const INT64_MIN = -(2n ** 63n);
const INT64_MAX = 2n ** 63n - 1n;

/** Raised for any condition that makes a line evaluate to `error`. */
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

const isBinaryOp = (ch: string): ch is BinaryOp =>
  ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '%';

const isDigit = (c: number): boolean => c >= 0x30 && c <= 0x39; // '0'..'9'
const isBlank = (c: number): boolean => c === 0x20 || c === 0x09; // ' ' or '\t'

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

/**
 * Evaluates one expression using an operator-precedence (shunting-yard)
 * parser, so deeply nested input cannot exhaust the call stack.
 * @throws {CalcError} on syntax errors, division by zero or overflow.
 */
export function evaluate(line: string): bigint {
  const values: bigint[] = [];
  const ops: StackOp[] = [];
  let expectOperand = true;

  const pop = (): bigint => {
    const v = values.pop();
    if (v === undefined) throw new Error('internal error: operand stack underflow');
    return v;
  };

  const reduce = (): void => {
    const op = ops.pop();
    if (op === undefined || op === '(') throw new Error('internal error: bad operator stack');
    if (op === 'neg') {
      values.push(checked(-pop()));
    } else {
      const b = pop();
      const a = pop();
      values.push(applyBinary(op, a, b));
    }
  };

  const top = (): StackOp | undefined => ops[ops.length - 1];

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
    } else if (isBinaryOp(ch)) {
      const prec = PRECEDENCE[ch];
      for (let t = top(); t !== undefined && t !== '(' && PRECEDENCE[t] >= prec; t = top()) {
        reduce();
      }
      ops.push(ch);
      expectOperand = true;
    } else if (ch === ')') {
      for (let t = top(); t !== undefined && t !== '('; t = top()) reduce();
      if (ops.length === 0) throw new CalcError('unbalanced parentheses');
      ops.pop();
    } else {
      throw new CalcError('syntax error');
    }
    i++;
  }

  if (expectOperand) throw new CalcError('missing operand');
  while (ops.length > 0) {
    if (top() === '(') throw new CalcError('unbalanced parentheses');
    reduce();
  }
  return pop();
}

const BLANK_LINE = /^[ \t]*$/;

/** Returns the output line for one input line, or `null` for blank lines. */
export function processLine(line: string): string | null {
  if (BLANK_LINE.test(line)) return null;
  try {
    return evaluate(line).toString();
  } catch (err) {
    if (err instanceof CalcError) return 'error';
    throw err;
  }
}
