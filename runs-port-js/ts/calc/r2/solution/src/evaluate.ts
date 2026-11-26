/**
 * Signed 64-bit integer expression evaluator.
 *
 * Grammar (spaces and tabs may separate any two tokens):
 *
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 */

const INT64_MIN = -(2n ** 63n);
const INT64_MAX = 2n ** 63n - 1n;

/** Thrown for any condition that makes a line evaluate to `error`. */
export class EvalError extends Error {
  override name = 'EvalError';
}

const fail = (message: string): never => {
  throw new EvalError(message);
};

const checked = (value: bigint): bigint =>
  value < INT64_MIN || value > INT64_MAX ? fail('overflow') : value;

const CH_TAB = 9;
const CH_SPACE = 32;
const CH_PERCENT = 37;
const CH_LPAREN = 40;
const CH_RPAREN = 41;
const CH_STAR = 42;
const CH_PLUS = 43;
const CH_MINUS = 45;
const CH_SLASH = 47;
const CH_0 = 48;
const CH_9 = 57;

type BinaryOp =
  | typeof CH_PLUS
  | typeof CH_MINUS
  | typeof CH_STAR
  | typeof CH_SLASH
  | typeof CH_PERCENT;

// Operator stack markers; binary operators are stored as their character code.
const LPAREN = 0;
const NEGATE = 1;

type StackOp = typeof LPAREN | typeof NEGATE | BinaryOp;

const isDigit = (c: number): boolean => c >= CH_0 && c <= CH_9;

const precedence = (op: StackOp): number => {
  switch (op) {
    case CH_PLUS:
    case CH_MINUS:
      return 1;
    case CH_STAR:
    case CH_SLASH:
    case CH_PERCENT:
      return 2;
    case NEGATE:
      return 3;
    case LPAREN:
      return 0;
  }
};

function applyBinary(op: BinaryOp, a: bigint, b: bigint): bigint {
  switch (op) {
    case CH_PLUS:
      return checked(a + b);
    case CH_MINUS:
      return checked(a - b);
    case CH_STAR:
      return checked(a * b);
    case CH_SLASH:
      if (b === 0n) fail('division by zero');
      return checked(a / b); // BigInt division truncates toward zero
    case CH_PERCENT:
      if (b === 0n) fail('division by zero');
      return a % b; // sign follows the dividend; never overflows
  }
}

/**
 * Evaluate one expression as signed 64-bit integer arithmetic.
 *
 * Uses an iterative operator-precedence (shunting-yard) parser so arbitrarily
 * deep nesting cannot exhaust the call stack.
 *
 * @returns the value, or `null` when the line is blank
 * @throws {EvalError} on syntax error, division by zero or overflow
 */
export function evaluate(line: string): bigint | null {
  const values: bigint[] = [];
  const ops: StackOp[] = [];
  let expectOperand = true;
  let sawToken = false;

  const pop = (): bigint => {
    const v = values.pop();
    if (v === undefined) throw new Error('internal error: value stack underflow');
    return v;
  };

  const reduceTop = (): void => {
    const op = ops.pop();
    if (op === undefined || op === LPAREN) {
      throw new Error('internal error: unexpected operator stack state');
    }
    if (op === NEGATE) {
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
    if (c === CH_SPACE || c === CH_TAB) {
      i++;
      continue;
    }
    sawToken = true;

    if (expectOperand) {
      if (isDigit(c)) {
        const start = i;
        while (i < n && isDigit(line.charCodeAt(i))) i++;
        values.push(checked(BigInt(line.slice(start, i))));
        expectOperand = false;
        continue;
      }
      if (c === CH_MINUS) ops.push(NEGATE);
      else if (c === CH_LPAREN) ops.push(LPAREN);
      else fail('expected operand');
      i++;
      continue;
    }

    switch (c) {
      case CH_PLUS:
      case CH_MINUS:
      case CH_STAR:
      case CH_SLASH:
      case CH_PERCENT: {
        // All binary operators are left-associative.
        const p = precedence(c);
        for (let t = top(); t !== undefined && precedence(t) >= p; t = top()) reduceTop();
        ops.push(c);
        expectOperand = true;
        break;
      }
      case CH_RPAREN: {
        for (let t = top(); t !== undefined && t !== LPAREN; t = top()) reduceTop();
        if (ops.length === 0) fail('unbalanced parenthesis');
        ops.pop();
        break;
      }
      default:
        fail('unexpected character');
    }
    i++;
  }

  if (!sawToken) return null;
  if (expectOperand) fail('missing operand');
  for (let t = top(); t !== undefined; t = top()) {
    if (t === LPAREN) fail('unbalanced parenthesis');
    reduceTop();
  }
  return pop();
}
