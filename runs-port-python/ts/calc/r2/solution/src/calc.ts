/**
 * Line-oriented 64-bit signed integer expression evaluator.
 *
 * Parsing uses an explicit operator stack (shunting-yard) so that deeply
 * nested input cannot exhaust the call stack.
 */

export const INT_MIN = -(1n << 63n);
export const INT_MAX = (1n << 63n) - 1n;

/** Raised for any syntax, domain, or overflow error in an expression. */
export class CalcError extends Error {
  override name = 'CalcError';
}

type BinaryOp = '+' | '-' | '*' | '/' | '%';
type StackOp = BinaryOp | 'neg' | '(';

const PRECEDENCE: Readonly<Record<Exclude<StackOp, '('>, number>> = {
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
};

const CH_TAB = 0x09;
const CH_SPACE = 0x20;
const CH_0 = 0x30;
const CH_9 = 0x39;

const isDigit = (c: number): boolean => c >= CH_0 && c <= CH_9;
const isBlank = (c: number): boolean => c === CH_SPACE || c === CH_TAB;

function checked(value: bigint): bigint {
  if (value < INT_MIN || value > INT_MAX) throw new CalcError('overflow');
  return value;
}

function applyOp(op: Exclude<StackOp, '('>, values: bigint[]): void {
  const top = values.length - 1;
  if (op === 'neg') {
    values[top] = checked(-values[top]!);
    return;
  }
  const b = values.pop()!;
  const a = values[top - 1]!;
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
      if (b === 0n) throw new CalcError('division by zero');
      result = a / b; // BigInt division truncates toward zero.
      break;
    case '%':
      if (b === 0n) throw new CalcError('division by zero');
      result = a % b; // Sign follows the dividend; never overflows.
      break;
  }
  values[top - 1] = checked(result);
}

/** Pops and applies operators while `shouldApply` holds for the stack top. */
function reduceWhile(ops: StackOp[], values: bigint[], shouldApply: (op: Exclude<StackOp, '('>) => boolean): void {
  while (ops.length > 0) {
    const op = ops[ops.length - 1]!;
    if (op === '(' || !shouldApply(op)) return;
    ops.pop();
    applyOp(op, values);
  }
}

/** Evaluates a single expression, throwing CalcError on any failure. */
export function evaluate(line: string): bigint {
  const values: bigint[] = [];
  const ops: StackOp[] = [];
  let expectOperand = true;
  const end = line.length;
  let pos = 0;

  while (pos < end) {
    const c = line.charCodeAt(pos);
    if (isBlank(c)) {
      pos++;
      continue;
    }

    if (isDigit(c)) {
      if (!expectOperand) throw new CalcError('unexpected number');
      const start = pos;
      while (pos < end && isDigit(line.charCodeAt(pos))) pos++;
      values.push(checked(BigInt(line.slice(start, pos))));
      expectOperand = false;
      continue;
    }

    const tok = line[pos]!;
    pos++;
    if (expectOperand) {
      if (tok === '-') ops.push('neg');
      else if (tok === '(') ops.push('(');
      else throw new CalcError(`unexpected ${JSON.stringify(tok)}`);
      continue;
    }

    switch (tok) {
      case ')':
        reduceWhile(ops, values, () => true);
        if (ops.length === 0) throw new CalcError("unbalanced ')'");
        ops.pop();
        break;
      case '+':
      case '-':
      case '*':
      case '/':
      case '%': {
        const prec = PRECEDENCE[tok];
        reduceWhile(ops, values, (op) => PRECEDENCE[op] >= prec);
        ops.push(tok);
        expectOperand = true;
        break;
      }
      default:
        throw new CalcError(`unexpected ${JSON.stringify(tok)}`);
    }
  }

  if (expectOperand) throw new CalcError('missing operand');
  while (ops.length > 0) {
    const op = ops.pop()!;
    if (op === '(') throw new CalcError("unbalanced '('");
    applyOp(op, values);
  }
  return values[0]!;
}

const isBlankLine = (line: string): boolean => {
  for (let i = 0; i < line.length; i++) {
    if (!isBlank(line.charCodeAt(i))) return false;
  }
  return true;
};

/** Evaluates each non-blank line, yielding its value or "error". */
export function* run(lines: Iterable<string>): Generator<string> {
  for (const line of lines) {
    if (isBlankLine(line)) continue;
    try {
      yield evaluate(line).toString();
    } catch (err) {
      if (!(err instanceof CalcError)) throw err;
      yield 'error';
    }
  }
}
