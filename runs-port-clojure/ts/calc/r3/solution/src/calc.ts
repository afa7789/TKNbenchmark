/**
 * Line-oriented evaluator for signed 64-bit integer expressions.
 *
 * Grammar:
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *
 * The parser is an operator-precedence (shunting-yard) evaluator driven by
 * explicit stacks, so arbitrarily deep nesting never exhausts the call stack.
 */

const INT64_MIN = -(1n << 63n);
const INT64_MAX = (1n << 63n) - 1n;

/** Signals that the current line cannot be evaluated. */
export class EvalError extends Error {
  override name = 'EvalError';
}

type BinaryOp = '+' | '-' | '*' | '/' | '%';

/** Entries on the operator stack: binary operators, unary negation, or an open parenthesis. */
type StackOp = BinaryOp | 'neg' | '(';

const PRECEDENCE: Readonly<Record<StackOp, number>> = {
  '(': 0,
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
};

function isDigit(code: number): boolean {
  return code >= 48 && code <= 57; // '0'..'9'
}

function isBlank(code: number): boolean {
  return code === 32 || code === 9; // space, tab
}

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
      return checked(a / b); // BigInt division truncates toward zero
    case '%':
      if (b === 0n) throw new EvalError('division by zero');
      return a % b; // sign follows the dividend; never overflows
  }
}

class Evaluator {
  private readonly values: bigint[] = [];
  private readonly ops: StackOp[] = [];

  pushValue(value: bigint): void {
    this.values.push(value);
  }

  pushOp(op: StackOp): void {
    this.ops.push(op);
  }

  /** Applies stacked operators whose precedence is at least `minPrecedence`. */
  reduce(minPrecedence: number): void {
    const { ops, values } = this;
    while (ops.length > 0) {
      const top = ops[ops.length - 1]!;
      if (top === '(' || PRECEDENCE[top] < minPrecedence) return;
      ops.pop();
      if (top === 'neg') {
        values.push(checked(-values.pop()!));
      } else {
        const rhs = values.pop()!;
        const lhs = values.pop()!;
        values.push(applyBinary(top, lhs, rhs));
      }
    }
  }

  /** Reduces back to the matching '(' and discards it. */
  closeParen(): void {
    this.reduce(1);
    if (this.ops.pop() !== '(') throw new EvalError("unmatched ')'");
  }

  finish(): bigint {
    this.reduce(1);
    if (this.ops.length > 0) throw new EvalError("expected ')'");
    return this.values.pop()!;
  }
}

/**
 * Evaluates one expression line and returns its value.
 * Throws {@link EvalError} when the line is syntactically invalid or the
 * computation divides by zero or overflows 64 bits.
 */
export function evaluate(line: string): bigint {
  const evaluator = new Evaluator();
  const n = line.length;
  // When true, the next token must start an operand (number, '-', or '(').
  let expectOperand = true;
  let i = 0;

  while (i < n) {
    const code = line.charCodeAt(i);
    if (isBlank(code)) {
      i++;
      continue;
    }

    if (isDigit(code)) {
      if (!expectOperand) throw new EvalError('unexpected number');
      const start = i;
      while (i < n && isDigit(line.charCodeAt(i))) i++;
      const literal = BigInt(line.slice(start, i));
      if (literal > INT64_MAX) throw new EvalError('literal out of range');
      evaluator.pushValue(literal);
      expectOperand = false;
      continue;
    }

    const ch = line[i]!;
    i++;
    if (expectOperand) {
      if (ch === '-') evaluator.pushOp('neg');
      else if (ch === '(') evaluator.pushOp('(');
      else throw new EvalError(`unexpected ${JSON.stringify(ch)}`);
      continue;
    }

    switch (ch) {
      case '+':
      case '-':
      case '*':
      case '/':
      case '%':
        // Left-associative: first apply everything of equal or higher precedence.
        evaluator.reduce(PRECEDENCE[ch]);
        evaluator.pushOp(ch);
        expectOperand = true;
        break;
      case ')':
        evaluator.closeParen();
        break;
      default:
        throw new EvalError(`unexpected ${JSON.stringify(ch)}`);
    }
  }

  if (expectOperand) throw new EvalError('unexpected end of input');
  return evaluator.finish();
}

function isBlankLine(line: string): boolean {
  for (let i = 0; i < line.length; i++) {
    if (!isBlank(line.charCodeAt(i))) return false;
  }
  return true;
}

/**
 * Returns the output for one input line: the value, "error", or null for a
 * blank line (which produces no output).
 */
export function evalLine(line: string): string | null {
  if (isBlankLine(line)) return null;
  try {
    return evaluate(line).toString();
  } catch (e) {
    if (e instanceof EvalError) return 'error';
    throw e;
  }
}
