/**
 * Signed 64-bit integer expression evaluator.
 *
 * Grammar:
 *   expr    := term    (('+' | '-') term)*
 *   term    := unary   (('*' | '/' | '%') unary)*
 *   unary   := '-' unary | primary
 *   primary := NUMBER | '(' expr ')'
 *
 * Parsing uses an explicit operator stack (shunting-yard) rather than recursion,
 * so arbitrarily deep nesting cannot overflow the call stack.
 */

export const INT64_MIN = -(1n << 63n);
export const INT64_MAX = (1n << 63n) - 1n;

type BinaryOp = '+' | '-' | '*' | '/' | '%';
/** Operator-stack entries: binary operators, unary negation, or an open parenthesis. */
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

const CH_TAB = 0x09;
const CH_SPACE = 0x20;
const CH_0 = 0x30;
const CH_9 = 0x39;

const inRange = (v: bigint): bigint | undefined => (v < INT64_MIN || v > INT64_MAX ? undefined : v);

/** Applies a binary operator; `undefined` signals overflow or division by zero. */
function applyBinary(op: BinaryOp, a: bigint, b: bigint): bigint | undefined {
  switch (op) {
    case '+':
      return inRange(a + b);
    case '-':
      return inRange(a - b);
    case '*':
      return inRange(a * b);
    case '/':
      // BigInt division truncates toward zero; only MIN / -1 can overflow.
      return b === 0n ? undefined : inRange(a / b);
    case '%':
      // BigInt remainder takes the dividend's sign; MIN % -1 is 0, not an error.
      return b === 0n ? undefined : a % b;
  }
}

const isBlank = (c: number): boolean => c === CH_SPACE || c === CH_TAB;

/** Returns true if the line holds nothing but spaces and tabs. */
export function isBlankLine(line: string): boolean {
  for (let i = 0; i < line.length; i++) {
    if (!isBlank(line.charCodeAt(i))) return false;
  }
  return true;
}

/**
 * Evaluates one expression. Returns `undefined` on any syntax error,
 * division by zero, or 64-bit overflow.
 */
export function evaluate(src: string): bigint | undefined {
  const values: bigint[] = [];
  const ops: StackOp[] = [];

  /** Pops and applies the top operator; `false` on arithmetic error. */
  const reduceTop = (): boolean => {
    const op = ops.pop();
    if (op === undefined || op === '(') return false;
    const b = values.pop();
    if (b === undefined) return false;
    if (op === 'neg') {
      const r = inRange(-b);
      if (r === undefined) return false;
      values.push(r);
      return true;
    }
    const a = values.pop();
    if (a === undefined) return false;
    const r = applyBinary(op, a, b);
    if (r === undefined) return false;
    values.push(r);
    return true;
  };

  /** Reduces while the stack top binds at least as tightly as `prec` (left-assoc). */
  const reduceWhile = (prec: number): boolean => {
    for (let top = ops.at(-1); top !== undefined && top !== '(' && PRECEDENCE[top] >= prec; top = ops.at(-1)) {
      if (!reduceTop()) return false;
    }
    return true;
  };

  let expectOperand = true;
  const n = src.length;
  let i = 0;

  while (i < n) {
    const c = src.charCodeAt(i);
    if (isBlank(c)) {
      i++;
      continue;
    }

    if (expectOperand) {
      if (c >= CH_0 && c <= CH_9) {
        const start = i;
        while (i < n && src.charCodeAt(i) >= CH_0 && src.charCodeAt(i) <= CH_9) i++;
        const literal = BigInt(src.slice(start, i));
        if (literal > INT64_MAX) return undefined;
        values.push(literal);
        expectOperand = false;
        continue;
      }
      const ch = src[i];
      if (ch === '-') ops.push('neg');
      else if (ch === '(') ops.push('(');
      else return undefined;
      i++;
      continue;
    }

    const ch = src[i];
    switch (ch) {
      case '+':
      case '-':
      case '*':
      case '/':
      case '%':
        if (!reduceWhile(PRECEDENCE[ch])) return undefined;
        ops.push(ch);
        expectOperand = true;
        break;
      case ')':
        if (!reduceWhile(1)) return undefined;
        if (ops.pop() !== '(') return undefined;
        break;
      default:
        return undefined;
    }
    i++;
  }

  if (expectOperand) return undefined;
  while (ops.length > 0) {
    if (!reduceTop()) return undefined;
  }
  return values.length === 1 ? values[0] : undefined;
}
