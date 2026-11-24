/**
 * Signed 64-bit integer expression evaluator.
 *
 * Grammar:
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *
 * Parsing is iterative (operator-precedence with explicit stacks) so that
 * deeply nested input cannot exhaust the call stack.
 */

const INT64_MIN = -(1n << 63n);
const INT64_MAX = (1n << 63n) - 1n;

/** Thrown for any syntax, domain, or overflow error. */
export class CalcError extends Error {
  override name = 'CalcError';
}

type BinaryOp = '+' | '-' | '*' | '/' | '%';
type StackOp = BinaryOp | 'neg' | '(';

const PRECEDENCE: Readonly<Record<BinaryOp, number>> = {
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
};

const CH_SPACE = 0x20;
const CH_TAB = 0x09;
const CH_0 = 0x30;
const CH_9 = 0x39;

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
      return checked(a / b); // BigInt division truncates toward zero.
    case '%':
      if (b === 0n) throw new CalcError('division by zero');
      return a % b; // Sign follows the dividend; never overflows.
  }
}

function isBinaryOp(c: string): c is BinaryOp {
  return c === '+' || c === '-' || c === '*' || c === '/' || c === '%';
}

/** Evaluates one expression. Throws CalcError on any error. */
export function evaluate(src: string): bigint {
  const values: bigint[] = [];
  const ops: StackOp[] = [];
  let expectOperand = true;

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

  const len = src.length;
  let i = 0;
  while (i < len) {
    const code = src.charCodeAt(i);
    if (code === CH_SPACE || code === CH_TAB) {
      i++;
      continue;
    }

    if (code >= CH_0 && code <= CH_9) {
      if (!expectOperand) throw new CalcError('unexpected number');
      const start = i;
      while (i < len) {
        const c = src.charCodeAt(i);
        if (c < CH_0 || c > CH_9) break;
        i++;
      }
      values.push(checked(BigInt(src.slice(start, i))));
      expectOperand = false;
      continue;
    }

    const ch = src[i]!;
    i++;

    if (expectOperand) {
      if (ch === '-') ops.push('neg');
      else if (ch === '(') ops.push('(');
      else throw new CalcError(`unexpected '${ch}'`);
      continue;
    }

    if (isBinaryOp(ch)) {
      const prec = PRECEDENCE[ch];
      for (;;) {
        const top = ops.at(-1);
        if (top === undefined || top === '(') break;
        if (top !== 'neg' && PRECEDENCE[top] < prec) break;
        reduceTop();
      }
      ops.push(ch);
      expectOperand = true;
    } else if (ch === ')') {
      for (;;) {
        const top = ops.at(-1);
        if (top === undefined) throw new CalcError("unmatched ')'");
        if (top === '(') break;
        reduceTop();
      }
      ops.pop();
    } else {
      throw new CalcError(`unexpected '${ch}'`);
    }
  }

  if (expectOperand) throw new CalcError('missing operand');
  while (ops.length > 0) {
    if (ops.at(-1) === '(') throw new CalcError("unmatched '('");
    reduceTop();
  }
  return values[0]!;
}

/** Returns true if the line contains only spaces and tabs. */
export function isBlank(line: string): boolean {
  for (let i = 0; i < line.length; i++) {
    const c = line.charCodeAt(i);
    if (c !== CH_SPACE && c !== CH_TAB) return false;
  }
  return true;
}

/** Produces the output line for one input line, or null if nothing is printed. */
export function evaluateLine(line: string): string | null {
  if (isBlank(line)) return null;
  try {
    return evaluate(line).toString();
  } catch (err) {
    if (err instanceof CalcError) return 'error';
    throw err;
  }
}
