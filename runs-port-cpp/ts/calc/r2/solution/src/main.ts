// calc: a 64-bit signed integer expression evaluator.
//
// Reads one expression per line from standard input and prints its value or
// "error". Parsing uses an explicit-stack operator-precedence algorithm so that
// deeply nested input cannot overflow the call stack.

import { readFileSync, writeSync } from 'node:fs';

const INT_MAX = 9223372036854775807n;
const INT_MIN = -9223372036854775808n;

/** Thrown internally to abort evaluation of the current line. */
class EvalError extends Error {}

function fail(): never {
  throw new EvalError();
}

/** Returns `value` if it fits in a signed 64-bit integer, otherwise fails. */
const checked = (value: bigint): bigint => (value < INT_MIN || value > INT_MAX ? fail() : value);

// ---------- operators ----------

type BinaryOp = '+' | '-' | '*' | '/' | '%';
/** Operator-stack entries: binary operators, unary negation, and an open parenthesis. */
type Op = BinaryOp | 'neg' | '(';

const PRECEDENCE: Readonly<Record<Op, number>> = {
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
  '(': 0,
};

const isBinaryOp = (c: string): c is BinaryOp =>
  c === '+' || c === '-' || c === '*' || c === '/' || c === '%';

function applyBinary(op: BinaryOp, lhs: bigint, rhs: bigint): bigint {
  switch (op) {
    case '+':
      return checked(lhs + rhs);
    case '-':
      return checked(lhs - rhs);
    case '*':
      return checked(lhs * rhs);
    case '/':
      // BigInt division truncates toward zero; MIN / -1 overflows.
      return rhs === 0n ? fail() : checked(lhs / rhs);
    case '%':
      // Sign follows the dividend; MIN % -1 is 0 (never an error).
      return rhs === 0n ? fail() : lhs % rhs;
  }
}

const isBlank = (c: string): boolean => c === ' ' || c === '\t';
const isDigit = (c: string): boolean => c >= '0' && c <= '9';

// ---------- evaluator ----------

export class Evaluator {
  private readonly values: bigint[] = [];
  private readonly ops: Op[] = [];

  /** Returns the value of `line`, or `null` on any syntax or arithmetic error. */
  evaluate(line: string): bigint | null {
    this.values.length = 0;
    this.ops.length = 0;
    try {
      return this.run(line);
    } catch (e) {
      if (e instanceof EvalError) return null;
      throw e;
    }
  }

  private run(line: string): bigint {
    const { values, ops } = this;
    const n = line.length;
    let expectOperand = true;
    let i = 0;

    while (i < n) {
      const c = line[i];
      if (isBlank(c)) {
        i++;
        continue;
      }
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
      } else if (c === ')') {
        while (ops.length > 0 && ops[ops.length - 1] !== '(') this.reduce();
        if (ops.length === 0) fail(); // unbalanced ')'
        ops.pop();
      } else {
        const op = c;
        if (!isBinaryOp(op)) fail();
        // All binary operators are left-associative.
        while (ops.length > 0 && PRECEDENCE[ops[ops.length - 1]] >= PRECEDENCE[op]) this.reduce();
        ops.push(op);
        expectOperand = true;
      }
      i++;
    }

    if (expectOperand) fail(); // missing operand (or empty)
    while (ops.length > 0) {
      if (ops[ops.length - 1] === '(') fail(); // unbalanced '('
      this.reduce();
    }
    if (values.length !== 1) fail();
    return values[0];
  }

  /** Applies the operator on top of the stack. */
  private reduce(): void {
    const { values, ops } = this;
    const op = ops.pop()!;
    if (op === '(') throw new Error('unreachable: reduce() on an open parenthesis');
    if (op === 'neg') {
      values.push(checked(-values.pop()!));
      return;
    }
    const rhs = values.pop()!;
    const lhs = values.pop()!;
    values.push(applyBinary(op, lhs, rhs));
  }
}

const isBlankLine = (line: string): boolean => /^[ \t]*$/.test(line);

function main(): void {
  // latin1 keeps a 1:1 byte-to-char mapping, so arbitrary bytes are handled safely.
  const text = readFileSync(0).toString('latin1');
  const evaluator = new Evaluator();
  const output: string[] = [];

  const lines = text.split('\n');
  if (text.endsWith('\n')) lines.pop();
  for (const line of lines) {
    if (isBlankLine(line)) continue;
    const value = evaluator.evaluate(line);
    output.push(value === null ? 'error' : value.toString());
  }

  if (output.length > 0) writeSync(1, output.join('\n') + '\n');
}

main();
