// calc: a 64-bit signed integer expression evaluator.
//
// Reads one expression per line from standard input and prints its value or
// "error". Parsing uses explicit operator/value stacks (shunting-yard) rather
// than recursion, so arbitrarily deep nesting cannot overflow the call stack.

import { readFileSync } from 'node:fs';

const INT_MAX = (1n << 63n) - 1n;
const INT_MIN = -(1n << 63n);

type BinaryOp = '+' | '-' | '*' | '/' | '%';
type Op = BinaryOp | 'neg' | '(';

const PRECEDENCE: Readonly<Record<Op, number>> = {
  '(': 0,
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
};

const isBinaryOp = (c: string): c is BinaryOp =>
  c === '+' || c === '-' || c === '*' || c === '/' || c === '%';

const isDigit = (c: string): boolean => c >= '0' && c <= '9';

const inRange = (v: bigint): boolean => v >= INT_MIN && v <= INT_MAX;

/** Signals any evaluation failure: syntax, overflow, or division by zero. */
class EvalError extends Error {}

const fail = (): never => {
  throw new EvalError();
};

const checked = (v: bigint): bigint => (inRange(v) ? v : fail());

/** Applies a binary operator with exact 64-bit signed semantics. */
function applyBinary(op: BinaryOp, a: bigint, b: bigint): bigint {
  switch (op) {
    case '+':
      return checked(a + b);
    case '-':
      return checked(a - b);
    case '*':
      return checked(a * b);
    case '/':
      // BigInt division truncates toward zero; only MIN / -1 overflows.
      return b === 0n ? fail() : checked(a / b);
    case '%':
      // BigInt remainder follows the dividend's sign; MIN % -1 is 0.
      return b === 0n ? fail() : a % b;
  }
}

class Evaluator {
  readonly #values: bigint[] = [];
  readonly #ops: Op[] = [];

  /** Returns the value of `line`, or `undefined` on any error. */
  evaluate(line: string): bigint | undefined {
    this.#values.length = 0;
    this.#ops.length = 0;
    try {
      return this.#run(line);
    } catch (e) {
      if (e instanceof EvalError) return undefined;
      throw e;
    }
  }

  #run(line: string): bigint {
    const values = this.#values;
    const ops = this.#ops;
    const n = line.length;
    let expectOperand = true;
    let i = 0;

    for (;;) {
      while (i < n && (line[i] === ' ' || line[i] === '\t')) i++;
      if (i === n) break;
      const c = line[i];

      if (expectOperand) {
        if (isDigit(c)) {
          const start = i;
          while (i < n && isDigit(line[i])) i++;
          values.push(checked(BigInt(line.slice(start, i))));
          expectOperand = false;
          continue;
        }
        if (c === '-') ops.push('neg');
        else if (c === '(') ops.push('(');
        else fail();
        i++;
        continue;
      }

      if (c === ')') {
        while (ops.length > 0 && ops[ops.length - 1] !== '(') this.#reduce();
        if (ops.length === 0) fail();
        ops.pop();
      } else if (isBinaryOp(c)) {
        // Left associativity: reduce operators of equal or higher precedence.
        const prec = PRECEDENCE[c];
        while (ops.length > 0 && PRECEDENCE[ops[ops.length - 1]] >= prec) this.#reduce();
        ops.push(c);
        expectOperand = true;
      } else {
        fail();
      }
      i++;
    }

    if (expectOperand) fail();
    while (ops.length > 0) {
      if (ops[ops.length - 1] === '(') fail();
      this.#reduce();
    }
    return values[values.length - 1];
  }

  /** Applies the operator on top of the stack to its operand(s). */
  #reduce(): void {
    const values = this.#values;
    const op = this.#ops.pop()!;
    if (op === 'neg') {
      values[values.length - 1] = checked(-values[values.length - 1]);
      return;
    }
    if (op === '(') fail();
    const rhs = values.pop()!;
    values[values.length - 1] = applyBinary(op, values[values.length - 1], rhs);
  }
}

const isBlank = (line: string): boolean => /^[ \t]*$/.test(line);

function main(): void {
  // latin1 maps each byte to one char, so non-ASCII bytes are simply invalid tokens.
  const text = readFileSync(0, 'latin1');
  const lines = text.split('\n');
  if (lines[lines.length - 1] === '') lines.pop();

  const evaluator = new Evaluator();
  const out: string[] = [];
  for (const line of lines) {
    if (isBlank(line)) continue;
    out.push(evaluator.evaluate(line)?.toString() ?? 'error');
  }
  if (out.length === 0) return;

  process.stdout.write(out.join('\n') + '\n');
}

main();
