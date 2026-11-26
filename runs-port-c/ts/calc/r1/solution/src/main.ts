/**
 * calc: evaluates one 64-bit signed integer expression per input line.
 *
 * The parser is an iterative operator-precedence (shunting-yard) evaluator
 * with explicit stacks, so arbitrarily deep nesting cannot exhaust the call stack.
 */
import { readFileSync } from 'node:fs';

const INT64_MAX = 0x7fffffffffffffffn;

const CH_TAB = 0x09;
const CH_NL = 0x0a;
const CH_SPACE = 0x20;
const CH_LPAREN = 0x28;
const CH_RPAREN = 0x29;
const CH_STAR = 0x2a;
const CH_PLUS = 0x2b;
const CH_MINUS = 0x2d;
const CH_SLASH = 0x2f;
const CH_PERCENT = 0x25;
const CH_0 = 0x30;
const CH_9 = 0x39;

/** Operator codes stored on the operator stack. */
const Op = {
  Add: 0,
  Sub: 1,
  Mul: 2,
  Div: 3,
  Rem: 4,
  Neg: 5,
  LParen: 6,
} as const;
type Op = (typeof Op)[keyof typeof Op];

const PRECEDENCE: Readonly<Record<Op, number>> = {
  [Op.Add]: 1,
  [Op.Sub]: 1,
  [Op.Mul]: 2,
  [Op.Div]: 2,
  [Op.Rem]: 2,
  [Op.Neg]: 3,
  [Op.LParen]: 0, // '(' never pops
};

/** Signals any evaluation failure: syntax error, division by zero or overflow. */
class EvalError extends Error {}

const fail = (): never => {
  throw new EvalError();
};

/** Returns `v` if it fits in a signed 64-bit integer, otherwise fails. */
function checked(v: bigint): bigint {
  return BigInt.asIntN(64, v) === v ? v : fail();
}

function binaryOpFor(c: number): Op | undefined {
  switch (c) {
    case CH_PLUS: return Op.Add;
    case CH_MINUS: return Op.Sub;
    case CH_STAR: return Op.Mul;
    case CH_SLASH: return Op.Div;
    case CH_PERCENT: return Op.Rem;
    default: return undefined;
  }
}

const isBlank = (c: number): boolean => c === CH_SPACE || c === CH_TAB;
const isDigit = (c: number): boolean => c >= CH_0 && c <= CH_9;

class Evaluator {
  private readonly values: bigint[] = [];
  private readonly ops: Op[] = [];

  /** Evaluates `line[start..end)`; throws EvalError on any error. */
  evaluate(line: Uint8Array, start: number, end: number): bigint {
    const { values, ops } = this;
    values.length = 0;
    ops.length = 0;

    let expectOperand = true;
    let i = start;

    for (;;) {
      while (i < end && isBlank(line[i])) i++;
      if (i === end) break;

      const c = line[i];
      if (expectOperand) {
        if (isDigit(c)) {
          const digitsStart = i;
          while (i < end && isDigit(line[i])) i++;
          values.push(parseLiteral(line, digitsStart, i));
          expectOperand = false;
        } else if (c === CH_MINUS) {
          ops.push(Op.Neg);
          i++;
        } else if (c === CH_LPAREN) {
          ops.push(Op.LParen);
          i++;
        } else {
          fail();
        }
      } else {
        const op = binaryOpFor(c);
        if (op !== undefined) {
          this.reduce(PRECEDENCE[op]);
          ops.push(op);
          expectOperand = true;
        } else if (c === CH_RPAREN) {
          this.reduce(0);
          if (ops.length === 0) fail(); // unmatched ')'
          ops.pop(); // discard '('
        } else {
          fail();
        }
        i++;
      }
    }

    if (expectOperand) fail();
    this.reduce(0);
    if (ops.length !== 0 || values.length !== 1) fail();
    return values[0];
  }

  /** Pops and applies operators whose precedence is at least `minPrec`. */
  private reduce(minPrec: number): void {
    const { ops } = this;
    while (ops.length > 0) {
      const top = ops[ops.length - 1];
      if (top === Op.LParen || PRECEDENCE[top] < minPrec) break;
      ops.pop();
      this.apply(top);
    }
  }

  /** Applies `op` to the value stack. */
  private apply(op: Op): void {
    const { values } = this;
    if (op === Op.Neg) {
      if (values.length < 1) fail();
      values[values.length - 1] = checked(-values[values.length - 1]);
      return;
    }
    if (values.length < 2) fail();
    const b = values.pop()!;
    const a = values[values.length - 1];
    values[values.length - 1] = applyBinary(op, a, b);
  }
}

function applyBinary(op: Op, a: bigint, b: bigint): bigint {
  switch (op) {
    case Op.Add: return checked(a + b);
    case Op.Sub: return checked(a - b);
    case Op.Mul: return checked(a * b);
    // BigInt division truncates toward zero; remainder takes the dividend's sign.
    case Op.Div: return b === 0n ? fail() : checked(a / b);
    case Op.Rem: return b === 0n ? fail() : a % b;
    default: return fail();
  }
}

/** Parses the decimal digits in `line[start..end)`, failing if above INT64_MAX. */
function parseLiteral(line: Uint8Array, start: number, end: number): bigint {
  // Up to 15 digits fit exactly in a double; take the fast path for those.
  if (end - start <= 15) {
    let v = 0;
    for (let i = start; i < end; i++) v = v * 10 + (line[i] - CH_0);
    return BigInt(v);
  }
  let v = 0n;
  for (let i = start; i < end; i++) {
    v = v * 10n + BigInt(line[i] - CH_0);
    if (v > INT64_MAX) fail();
  }
  return v;
}

function isBlankLine(buf: Uint8Array, start: number, end: number): boolean {
  for (let i = start; i < end; i++) if (!isBlank(buf[i])) return false;
  return true;
}

function main(): void {
  const input = readFileSync(0);
  const evaluator = new Evaluator();
  const out: string[] = [];

  let start = 0;
  while (start < input.length) {
    let end = input.indexOf(CH_NL, start);
    if (end === -1) end = input.length;

    if (!isBlankLine(input, start, end)) {
      try {
        out.push(evaluator.evaluate(input, start, end).toString());
      } catch (e) {
        if (!(e instanceof EvalError)) throw e;
        out.push('error');
      }
    }
    start = end + 1;
  }

  if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
}

main();
