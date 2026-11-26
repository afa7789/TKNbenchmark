/**
 * Evaluates a single 64-bit signed integer expression.
 *
 * Parsing uses an iterative operator-precedence (shunting-yard) evaluator
 * with explicit stacks, so arbitrarily deep nesting cannot exhaust the
 * call stack.
 */

export const INT64_MIN = -(1n << 63n);
export const INT64_MAX = (1n << 63n) - 1n;

const CH_TAB = 0x09;
const CH_SPACE = 0x20;
const CH_PERCENT = 0x25;
const CH_LPAREN = 0x28;
const CH_RPAREN = 0x29;
const CH_STAR = 0x2a;
const CH_PLUS = 0x2b;
const CH_MINUS = 0x2d;
const CH_SLASH = 0x2f;
const CH_0 = 0x30;
const CH_9 = 0x39;

/** Operator held on the operator stack. */
type Op = '(' | 'neg' | '+' | '-' | '*' | '/' | '%';
type BinaryOp = Exclude<Op, '(' | 'neg'>;

const BINARY_OPS: ReadonlyMap<number, BinaryOp> = new Map([
  [CH_PLUS, '+'],
  [CH_MINUS, '-'],
  [CH_STAR, '*'],
  [CH_SLASH, '/'],
  [CH_PERCENT, '%'],
]);

function precedence(op: Op): number {
  switch (op) {
    case 'neg':
      return 3;
    case '*':
    case '/':
    case '%':
      return 2;
    case '+':
    case '-':
      return 1;
    case '(':
      return 0; // '(' never reduces by precedence
  }
}

export function isBlank(c: number): boolean {
  return c === CH_SPACE || c === CH_TAB;
}

function isDigit(c: number): boolean {
  return c >= CH_0 && c <= CH_9;
}

function inRange(v: bigint): boolean {
  return v >= INT64_MIN && v <= INT64_MAX;
}

/** Signals a syntax or arithmetic error; caught at the evaluate() boundary. */
class EvalError extends Error {}

function fail(): never {
  throw new EvalError();
}

/** Applies a binary operator, failing on overflow or division by zero. */
function applyBinary(op: BinaryOp, a: bigint, b: bigint): bigint {
  let result: bigint;
  switch (op) {
    case '+':
      result = a + b;
      break;
    case '-':
      result = a - b;
      break;
    case '*':
      result = a * b;
      break;
    case '/':
      if (b === 0n) fail();
      result = a / b; // BigInt division truncates toward zero
      break;
    case '%':
      if (b === 0n) fail();
      return a % b; // sign follows the dividend; never overflows
  }
  if (!inRange(result)) fail();
  return result;
}

class Evaluator {
  private readonly vals: bigint[] = [];
  private readonly ops: Op[] = [];
  private readonly line: Buffer;

  constructor(line: Buffer) {
    this.line = line;
  }

  run(): bigint {
    const { line, vals, ops } = this;
    const len = line.length;
    let wantOperand = true;
    let i = 0;

    for (;;) {
      while (i < len && isBlank(line[i])) i++;

      if (wantOperand) {
        if (i === len) fail();
        const c = line[i];
        if (c === CH_MINUS) {
          ops.push('neg');
          i++;
        } else if (c === CH_LPAREN) {
          ops.push('(');
          i++;
        } else if (isDigit(c)) {
          const start = i;
          do i++;
          while (i < len && isDigit(line[i]));
          const value = BigInt(line.toString('latin1', start, i));
          if (value > INT64_MAX) fail();
          vals.push(value);
          wantOperand = false;
        } else {
          fail();
        }
        continue;
      }

      if (i === len) break;

      const c = line[i++];
      if (c === CH_RPAREN) {
        this.reduceWhile(0);
        if (ops.pop() === undefined) fail(); // unmatched ')'
        continue;
      }
      const op = BINARY_OPS.get(c) ?? fail();
      this.reduceWhile(precedence(op));
      ops.push(op);
      wantOperand = true;
    }

    this.reduceWhile(0);
    if (ops.length !== 0) fail(); // unmatched '('
    return vals[0];
  }

  /** Reduces while the top operator binds at least as tightly as `prec`. */
  private reduceWhile(prec: number): void {
    const { ops } = this;
    while (ops.length > 0) {
      const top = ops[ops.length - 1];
      if (top === '(' || precedence(top) < prec) return;
      ops.pop();
      this.reduce(top);
    }
  }

  /** Applies `op` to the value stack. */
  private reduce(op: Exclude<Op, '('>): void {
    const { vals } = this;
    if (op === 'neg') {
      const v = -vals[vals.length - 1];
      if (!inRange(v)) fail();
      vals[vals.length - 1] = v;
      return;
    }
    const b = vals.pop()!;
    vals[vals.length - 1] = applyBinary(op, vals[vals.length - 1], b);
  }
}

/**
 * Evaluates the expression held in `line` (raw bytes, without the newline).
 * Returns the value, or `undefined` on any syntax or arithmetic error.
 */
export function evaluate(line: Buffer): bigint | undefined {
  try {
    return new Evaluator(line).run();
  } catch (err) {
    if (err instanceof EvalError) return undefined;
    throw err;
  }
}
