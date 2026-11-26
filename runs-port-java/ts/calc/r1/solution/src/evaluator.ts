/**
 * Evaluator for signed 64-bit integer expressions.
 *
 * ```
 * expr    := term    (('+' | '-') term)*
 * term    := unary   (('*' | '/' | '%') unary)*
 * unary   := '-' unary | primary
 * primary := NUMBER | '(' expr ')'
 * ```
 *
 * Parsing uses an explicit operator stack (shunting-yard) rather than recursion,
 * so arbitrarily deep nesting cannot exhaust the call stack. Any syntax error,
 * division by zero, or overflow makes the whole expression invalid.
 */

const INT64_MIN = -(1n << 63n);
const INT64_MAX = (1n << 63n) - 1n;

/** Digits in INT64_MAX; longer literals (ignoring leading zeros) always overflow. */
const MAX_LITERAL_DIGITS = 19;

const SPACE = 0x20;
const TAB = 0x09;
const DIGIT_0 = 0x30;
const DIGIT_9 = 0x39;
const PLUS = 0x2b;
const MINUS = 0x2d;
const STAR = 0x2a;
const SLASH = 0x2f;
const PERCENT = 0x25;
const LPAREN = 0x28;
const RPAREN = 0x29;

/** Operator-stack entries. Binary operators are stored as their character code. */
const OPEN_PAREN = -1;
const NEGATE = -2;

/** Thrown internally when the expression has no value; never escapes this module. */
class EvaluationError extends Error {}

const isSpace = (b: number): boolean => b === SPACE || b === TAB;
const isDigit = (b: number): boolean => b >= DIGIT_0 && b <= DIGIT_9;

function precedence(op: number): number {
  switch (op) {
    case NEGATE:
      return 3;
    case STAR:
    case SLASH:
    case PERCENT:
      return 2;
    case PLUS:
    case MINUS:
      return 1;
    default:
      return 0; // OPEN_PAREN: never reduced by precedence
  }
}

function checked(value: bigint): bigint {
  if (value < INT64_MIN || value > INT64_MAX) throw new EvaluationError();
  return value;
}

function applyBinary(op: number, a: bigint, b: bigint): bigint {
  switch (op) {
    case PLUS:
      return checked(a + b);
    case MINUS:
      return checked(a - b);
    case STAR:
      return checked(a * b);
    case SLASH:
      if (b === 0n) throw new EvaluationError();
      return checked(a / b); // BigInt division truncates toward zero
    case PERCENT:
      if (b === 0n) throw new EvaluationError();
      return a % b; // sign follows the dividend; MIN % -1 is 0
    default:
      throw new Error(`unknown operator ${op}`);
  }
}

class Machine {
  private readonly values: bigint[] = [];
  private readonly ops: number[] = [];

  pushValue(value: bigint): void {
    this.values.push(value);
  }

  pushOperator(op: number): void {
    this.ops.push(op);
  }

  /** Applies stacked operators that bind at least as tightly as a binary operator of `prec`. */
  reduceWhile(prec: number): void {
    const { ops } = this;
    while (ops.length > 0 && precedence(ops[ops.length - 1]) >= prec) {
      this.applyTop();
    }
  }

  /** Reduces up to and removes the innermost open parenthesis. */
  closeParen(): void {
    this.reduceWhile(1);
    if (this.ops.pop() !== OPEN_PAREN) throw new EvaluationError();
  }

  /** Reduces everything; fails if an open parenthesis remains. */
  finish(): bigint {
    this.reduceWhile(1);
    if (this.ops.length > 0) throw new EvaluationError();
    return this.values[0];
  }

  private applyTop(): void {
    const op = this.ops.pop()!;
    const { values } = this;
    if (op === NEGATE) {
      values.push(checked(-values.pop()!));
    } else {
      const b = values.pop()!;
      const a = values.pop()!;
      values.push(applyBinary(op, a, b));
    }
  }
}

/** Parses the digits starting at `start`; returns the literal value and the end offset. */
function scanNumber(src: Uint8Array, start: number, end: number): [bigint, number] {
  let pos = start;
  while (pos < end && src[pos] === DIGIT_0) pos++;
  const significant = pos;
  while (pos < end && isDigit(src[pos])) pos++;
  if (pos - significant > MAX_LITERAL_DIGITS) throw new EvaluationError();
  let digits = '0';
  for (let i = significant; i < pos; i++) digits += String.fromCharCode(src[i]);
  const value = BigInt(digits);
  if (value > INT64_MAX) throw new EvaluationError();
  return [value, pos];
}

function run(src: Uint8Array, start: number, end: number): bigint {
  const machine = new Machine();
  let expectOperand = true;
  let pos = start;

  while (true) {
    while (pos < end && isSpace(src[pos])) pos++;
    if (pos >= end) break;
    const c = src[pos];

    if (expectOperand) {
      if (c === MINUS) {
        machine.pushOperator(NEGATE);
        pos++;
      } else if (c === LPAREN) {
        machine.pushOperator(OPEN_PAREN);
        pos++;
      } else if (isDigit(c)) {
        const [value, next] = scanNumber(src, pos, end);
        machine.pushValue(value);
        pos = next;
        expectOperand = false;
      } else {
        throw new EvaluationError();
      }
    } else if (c === PLUS || c === MINUS || c === STAR || c === SLASH || c === PERCENT) {
      machine.reduceWhile(precedence(c)); // left-associative
      machine.pushOperator(c);
      expectOperand = true;
      pos++;
    } else if (c === RPAREN) {
      machine.closeParen();
      pos++;
    } else {
      throw new EvaluationError();
    }
  }

  if (expectOperand) throw new EvaluationError();
  return machine.finish();
}

/**
 * Returns the value of the expression in `src[start, end)`, or `undefined`
 * if it is malformed or not representable as a signed 64-bit integer.
 */
export function evaluate(src: Uint8Array, start = 0, end = src.length): bigint | undefined {
  try {
    return run(src, start, end);
  } catch (e) {
    if (e instanceof EvaluationError) return undefined;
    throw e;
  }
}

/** True if `src[start, end)` holds only spaces and tabs. */
export function isBlank(src: Uint8Array, start = 0, end = src.length): boolean {
  for (let i = start; i < end; i++) {
    if (!isSpace(src[i])) return false;
  }
  return true;
}
