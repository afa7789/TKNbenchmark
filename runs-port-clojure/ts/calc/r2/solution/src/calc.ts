/**
 * Line-oriented evaluator for signed 64-bit integer expressions.
 *
 * Grammar:
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *
 * Parsing is iterative (operator-precedence with explicit stacks), so deeply
 * nested input cannot overflow the call stack.
 */

const INT64_MIN = -(1n << 63n);
const INT64_MAX = (1n << 63n) - 1n;

/** Raised for any condition that makes a line evaluate to `error`. */
export class EvalError extends Error {}

type BinaryOp = '+' | '-' | '*' | '/' | '%';
type StackOp = BinaryOp | 'neg' | '(';

const PRECEDENCE: Record<BinaryOp, number> = { '+': 1, '-': 1, '*': 2, '/': 2, '%': 2 };

function checked(value: bigint): bigint {
  if (value < INT64_MIN || value > INT64_MAX) throw new EvalError('overflow');
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
      if (b === 0n) throw new EvalError('division by zero');
      return checked(a / b); // BigInt division truncates toward zero.
    case '%':
      if (b === 0n) throw new EvalError('division by zero');
      return a % b; // Sign follows the dividend; never overflows.
  }
}

const isBlank = (c: number): boolean => c === 0x20 || c === 0x09;
const isDigit = (c: number): boolean => c >= 0x30 && c <= 0x39;

/** Evaluates one expression. Throws EvalError on syntax or arithmetic errors. */
export function evaluate(line: string): bigint {
  const values: bigint[] = [];
  const ops: StackOp[] = [];
  let expectOperand = true;

  const reduceBinary = (): void => {
    const op = ops.pop() as BinaryOp;
    const b = values.pop()!;
    const a = values.pop()!;
    values.push(applyBinary(op, a, b));
  };

  // After an operand is complete, apply the unary minuses waiting for it.
  const operandDone = (): void => {
    while (ops.length > 0 && ops[ops.length - 1] === 'neg') {
      ops.pop();
      values.push(checked(-values.pop()!));
    }
    expectOperand = false;
  };

  const n = line.length;
  let i = 0;
  while (i < n) {
    const code = line.charCodeAt(i);
    if (isBlank(code)) {
      i++;
      continue;
    }

    if (expectOperand) {
      if (isDigit(code)) {
        let end = i + 1;
        while (end < n && isDigit(line.charCodeAt(end))) end++;
        const literal = BigInt(line.slice(i, end));
        if (literal > INT64_MAX) throw new EvalError('integer literal out of range');
        values.push(literal);
        i = end;
        operandDone();
        continue;
      }
      const c = line[i];
      if (c === '-') ops.push('neg');
      else if (c === '(') ops.push('(');
      else throw new EvalError('expected operand');
      i++;
      continue;
    }

    const c = line[i];
    if (c === ')') {
      while (ops.length > 0 && ops[ops.length - 1] !== '(') reduceBinary();
      if (ops.length === 0) throw new EvalError('unbalanced )');
      ops.pop();
      operandDone();
    } else if (c === '+' || c === '-' || c === '*' || c === '/' || c === '%') {
      const prec = PRECEDENCE[c];
      while (ops.length > 0) {
        const top = ops[ops.length - 1];
        if (top === '(' || top === 'neg' || PRECEDENCE[top] < prec) break;
        reduceBinary();
      }
      ops.push(c);
      expectOperand = true;
    } else {
      throw new EvalError('expected operator');
    }
    i++;
  }

  if (expectOperand) throw new EvalError('missing operand');
  while (ops.length > 0) {
    if (ops[ops.length - 1] === '(') throw new EvalError('expected )');
    reduceBinary();
  }
  return values[0];
}

/** Returns the output for one input line, or null for a blank line. */
export function evalLine(line: string): string | null {
  let blank = true;
  for (let i = 0; i < line.length; i++) {
    if (!isBlank(line.charCodeAt(i))) {
      blank = false;
      break;
    }
  }
  if (blank) return null;
  try {
    return evaluate(line).toString();
  } catch (e) {
    if (e instanceof EvalError) return 'error';
    throw e;
  }
}
