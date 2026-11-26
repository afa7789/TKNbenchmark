// calc: 64-bit signed integer expression evaluator (see SPEC.md).
//
// Each input line is evaluated with an iterative operator-precedence parser,
// so arbitrarily deep nesting cannot overflow the call stack.

import { readFileSync } from 'node:fs';

type Value = bigint;

const MIN: Value = -(1n << 63n);
const MAX: Value = (1n << 63n) - 1n;

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
const isBlank = (c: string): boolean => c === ' ' || c === '\t';
const isDigit = (c: string): boolean => c >= '0' && c <= '9';

const inRange = (v: Value): Value | undefined => (v < MIN || v > MAX ? undefined : v);

function applyBinary(op: BinaryOp, a: Value, b: Value): Value | undefined {
  switch (op) {
    case '+':
      return inRange(a + b);
    case '-':
      return inRange(a - b);
    case '*':
      return inRange(a * b);
    case '/':
      // BigInt division truncates toward zero, matching the spec.
      return b === 0n ? undefined : inRange(a / b);
    case '%':
      // BigInt remainder takes the sign of the dividend, matching the spec.
      return b === 0n ? undefined : a % b;
  }
}

class Evaluator {
  private readonly values: Value[] = [];
  private readonly ops: Op[] = [];

  /** Returns the value of `line`, or undefined on any syntax or arithmetic error. */
  evaluate(line: string): Value | undefined {
    this.values.length = 0;
    this.ops.length = 0;

    let expectOperand = true;
    let i = 0;
    const n = line.length;

    while (true) {
      while (i < n && isBlank(line[i])) i++;
      if (i === n) break;
      const c = line[i];

      if (expectOperand) {
        if (c === '-') {
          this.ops.push('neg');
          i++;
        } else if (c === '(') {
          this.ops.push('(');
          i++;
        } else if (isDigit(c)) {
          const start = i;
          while (i < n && isDigit(line[i])) i++;
          const v = BigInt(line.slice(start, i));
          if (v > MAX) return undefined;
          this.values.push(v);
          expectOperand = false;
        } else {
          return undefined;
        }
      } else if (c === ')') {
        if (!this.reduceWhile((op) => op !== '(')) return undefined;
        if (this.ops.length === 0) return undefined; // unmatched ')'
        this.ops.pop();
        i++;
      } else if (isBinaryOp(c)) {
        const p = PRECEDENCE[c];
        if (!this.reduceWhile((top) => PRECEDENCE[top] >= p)) return undefined;
        this.ops.push(c);
        expectOperand = true;
        i++;
      } else {
        return undefined;
      }
    }

    if (expectOperand) return undefined; // missing operand
    if (!this.reduceWhile((op) => op !== '(')) return undefined;
    if (this.ops.length !== 0 || this.values.length !== 1) return undefined; // unmatched '('
    return this.values[0];
  }

  /** Applies the top operator to the value stack. */
  private reduceOnce(): boolean {
    const op = this.ops.pop()!;
    const b = this.values.pop()!;
    let result: Value | undefined;
    if (op === 'neg') {
      result = inRange(-b);
    } else if (op === '(') {
      result = undefined;
    } else {
      const a = this.values.pop()!;
      result = applyBinary(op, a, b);
    }
    if (result === undefined) return false;
    this.values.push(result);
    return true;
  }

  private reduceWhile(pred: (op: Op) => boolean): boolean {
    while (this.ops.length > 0 && pred(this.ops[this.ops.length - 1])) {
      if (!this.reduceOnce()) return false;
    }
    return true;
  }
}

const isBlankLine = (line: string): boolean => {
  for (const c of line) if (!isBlank(c)) return false;
  return true;
};

function main(): void {
  // latin1 maps each byte to one character, so arbitrary bytes are handled losslessly.
  const input = readFileSync(0).toString('latin1');
  const lines = input.split('\n');
  if (lines[lines.length - 1] === '') lines.pop();

  const evaluator = new Evaluator();
  const output: string[] = [];
  for (const line of lines) {
    if (isBlankLine(line)) continue;
    output.push(evaluator.evaluate(line)?.toString() ?? 'error');
  }

  if (output.length > 0) process.stdout.write(output.join('\n') + '\n');
}

main();
