/**
 * Evaluator for signed 64-bit integer arithmetic expressions.
 *
 * Grammar:
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *
 * Parsing is iterative (operator-precedence with explicit stacks) so that
 * deeply nested input cannot overflow the call stack.
 */

const INT64_MIN = -(1n << 63n);
const INT64_MAX = (1n << 63n) - 1n;

/** Thrown for any syntax, division-by-zero, or overflow failure. */
export class EvalError extends Error {}

type BinaryOp = '+' | '-' | '*' | '/' | '%';
type StackOp = BinaryOp | 'neg' | '(';

const PRECEDENCE: Record<Exclude<StackOp, '('>, number> = {
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
};

const CH_SPACE = 0x20;
const CH_TAB = 0x09;
const CH_0 = 0x30;
const CH_9 = 0x39;

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

class Machine {
  private readonly values: bigint[] = [];
  private readonly ops: StackOp[] = [];

  pushValue(value: bigint): void {
    this.values.push(value);
  }

  pushOpen(): void {
    this.ops.push('(');
  }

  pushNegate(): void {
    this.ops.push('neg');
  }

  /** Reduce pending operators that bind at least as tightly, then push `op`. */
  pushBinary(op: BinaryOp): void {
    const prec = PRECEDENCE[op];
    for (;;) {
      const top = this.ops.at(-1);
      if (top === undefined || top === '(' || PRECEDENCE[top] < prec) break;
      this.reduceTop();
    }
    this.ops.push(op);
  }

  /** Reduce up to and including the matching '('. */
  close(): void {
    for (;;) {
      const top = this.ops.at(-1);
      if (top === undefined) throw new EvalError('unbalanced parenthesis');
      if (top === '(') {
        this.ops.pop();
        return;
      }
      this.reduceTop();
    }
  }

  finish(): bigint {
    while (this.ops.length > 0) {
      if (this.ops.at(-1) === '(') throw new EvalError('unbalanced parenthesis');
      this.reduceTop();
    }
    const result = this.values.pop();
    if (result === undefined || this.values.length > 0) throw new EvalError('malformed expression');
    return result;
  }

  private reduceTop(): void {
    const op = this.ops.pop() as Exclude<StackOp, '('>;
    if (op === 'neg') {
      const a = this.values.pop()!;
      this.values.push(checked(-a));
      return;
    }
    const b = this.values.pop()!;
    const a = this.values.pop()!;
    this.values.push(applyBinary(op, a, b));
  }
}

/** Returns true when the line contains only spaces and tabs. */
export function isBlank(line: string): boolean {
  for (let i = 0; i < line.length; i++) {
    const c = line.charCodeAt(i);
    if (c !== CH_SPACE && c !== CH_TAB) return false;
  }
  return true;
}

/** Evaluates one expression, throwing {@link EvalError} on failure. */
export function evaluate(source: string): bigint {
  const machine = new Machine();
  // true: the next token must start an operand; false: an operator or ')'.
  let expectOperand = true;
  let i = 0;
  const n = source.length;

  while (i < n) {
    const c = source.charCodeAt(i);
    if (c === CH_SPACE || c === CH_TAB) {
      i++;
      continue;
    }

    if (c >= CH_0 && c <= CH_9) {
      if (!expectOperand) throw new EvalError('unexpected number');
      const start = i;
      while (i < n) {
        const d = source.charCodeAt(i);
        if (d < CH_0 || d > CH_9) break;
        i++;
      }
      machine.pushValue(checked(BigInt(source.slice(start, i))));
      expectOperand = false;
      continue;
    }

    const ch = source[i];
    i++;
    if (expectOperand) {
      if (ch === '-') machine.pushNegate();
      else if (ch === '(') machine.pushOpen();
      else throw new EvalError(`unexpected '${ch}'`);
    } else {
      switch (ch) {
        case '+':
        case '-':
        case '*':
        case '/':
        case '%':
          machine.pushBinary(ch);
          expectOperand = true;
          break;
        case ')':
          machine.close();
          break;
        default:
          throw new EvalError(`unexpected '${ch}'`);
      }
    }
  }

  if (expectOperand) throw new EvalError('missing operand');
  return machine.finish();
}
