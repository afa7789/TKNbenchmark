/**
 * calc — a 64-bit signed integer expression evaluator.
 *
 * Parsing uses an explicit-stack operator-precedence algorithm, so arbitrarily
 * deep nesting cannot exhaust the call stack. Expressions are evaluated from
 * raw bytes so that any non-ASCII input is rejected exactly like other
 * characters outside the grammar.
 */

const INT64_MAX = (1n << 63n) - 1n;
const INT64_MIN = -(1n << 63n);

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

const Op = {
  LParen: 0,
  Add: 1,
  Sub: 2,
  Mul: 3,
  Div: 4,
  Mod: 5,
  Neg: 6,
} as const;
type Op = (typeof Op)[keyof typeof Op];

const PRECEDENCE: Readonly<Record<Op, number>> = {
  [Op.LParen]: 0,
  [Op.Add]: 1,
  [Op.Sub]: 1,
  [Op.Mul]: 2,
  [Op.Div]: 2,
  [Op.Mod]: 2,
  [Op.Neg]: 3,
};

const BINARY_OPS: ReadonlyMap<number, Op> = new Map<number, Op>([
  [CH_PLUS, Op.Add],
  [CH_MINUS, Op.Sub],
  [CH_STAR, Op.Mul],
  [CH_SLASH, Op.Div],
  [CH_PERCENT, Op.Mod],
]);

/** Thrown internally for any syntax, domain, or overflow error. */
class EvalError extends Error {}

function checked(value: bigint): bigint {
  if (value > INT64_MAX || value < INT64_MIN) throw new EvalError("overflow");
  return value;
}

/** Applies a binary operator with 64-bit overflow and zero-division checks. */
function applyBinary(op: Op, a: bigint, b: bigint): bigint {
  switch (op) {
    case Op.Add:
      return checked(a + b);
    case Op.Sub:
      return checked(a - b);
    case Op.Mul:
      return checked(a * b);
    case Op.Div:
      if (b === 0n) throw new EvalError("division by zero");
      return checked(a / b); // BigInt division truncates toward zero
    case Op.Mod:
      if (b === 0n) throw new EvalError("division by zero");
      return a % b; // sign follows the dividend; INT64_MIN % -1 is 0
    default:
      throw new EvalError("invalid operator");
  }
}

export function isBlank(c: number): boolean {
  return c === CH_SPACE || c === CH_TAB;
}

function isDigit(c: number): boolean {
  return c >= CH_0 && c <= CH_9;
}

/** Pops the top operator and applies it to the value stack. */
function applyTop(vals: bigint[], ops: Op[]): void {
  const op = ops.pop()!;
  if (op === Op.Neg) {
    vals.push(checked(-vals.pop()!));
    return;
  }
  const b = vals.pop()!;
  const a = vals.pop()!;
  vals.push(applyBinary(op, a, b));
}

function evaluateOrThrow(line: Uint8Array): bigint {
  const vals: bigint[] = [];
  const ops: Op[] = [];
  let wantOperand = true;
  let i = 0;
  const len = line.length;

  while (i < len) {
    const c = line[i];
    if (isBlank(c)) {
      i++;
      continue;
    }

    if (wantOperand) {
      if (isDigit(c)) {
        const start = i;
        while (i < len && isDigit(line[i])) i++;
        const digits = Buffer.from(line.buffer, line.byteOffset + start, i - start).toString("latin1");
        vals.push(checked(BigInt(digits)));
        wantOperand = false;
      } else if (c === CH_MINUS) {
        ops.push(Op.Neg);
        i++;
      } else if (c === CH_LPAREN) {
        ops.push(Op.LParen);
        i++;
      } else {
        throw new EvalError("unexpected character");
      }
      continue;
    }

    if (c === CH_RPAREN) {
      while (ops.length > 0 && ops[ops.length - 1] !== Op.LParen) applyTop(vals, ops);
      if (ops.length === 0) throw new EvalError("unbalanced ')'");
      ops.pop();
      i++;
      continue;
    }

    const op = BINARY_OPS.get(c);
    if (op === undefined) throw new EvalError("unexpected character");

    // All binary operators are left-associative.
    const prec = PRECEDENCE[op];
    while (ops.length > 0 && PRECEDENCE[ops[ops.length - 1]] >= prec) applyTop(vals, ops);
    ops.push(op);
    wantOperand = true;
    i++;
  }

  if (wantOperand) throw new EvalError("missing operand");
  while (ops.length > 0) {
    if (ops[ops.length - 1] === Op.LParen) throw new EvalError("unbalanced '('");
    applyTop(vals, ops);
  }
  return vals[0];
}

/**
 * Evaluates one expression. Returns its value, or `null` on any syntax error,
 * division by zero, or 64-bit overflow.
 */
export function evaluate(line: Uint8Array): bigint | null {
  try {
    return evaluateOrThrow(line);
  } catch (err) {
    if (err instanceof EvalError) return null;
    throw err;
  }
}
