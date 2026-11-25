/**
 * 64-bit signed integer expression evaluator.
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

const INT64_MIN = -(1n << 63n);
const INT64_MAX = (1n << 63n) - 1n;

type BinaryOp = '+' | '-' | '*' | '/' | '%';
type StackOp = BinaryOp | 'neg' | '(';

class EvalError extends Error {}

const PRECEDENCE: Record<Exclude<StackOp, '('>, number> = {
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  neg: 3,
};

function checked(value: bigint): bigint {
  if (value < INT64_MIN || value > INT64_MAX) throw new EvalError('overflow');
  return value;
}

function applyBinary(op: BinaryOp, a: bigint, b: bigint): bigint {
  switch (op) {
    case '+':
      return checked(a + b);
    case '-':
      return checked(a - b);
    case '*':
      return checked(a * b);
    case '/':
      if (b === 0n) throw new EvalError('division by zero');
      return checked(a / b);
    case '%':
      if (b === 0n) throw new EvalError('division by zero');
      return a % b;
  }
}

function isDigit(code: number): boolean {
  return code >= 48 && code <= 57;
}

function isBlank(code: number): boolean {
  return code === 32 || code === 9;
}

class Evaluator {
  readonly #values: bigint[] = [];
  readonly #ops: StackOp[] = [];

  #pop(): bigint {
    const v = this.#values.pop();
    if (v === undefined) throw new EvalError('missing operand');
    return v;
  }

  /** Applies the operator on top of the stack to its operands. */
  #reduce(): void {
    const op = this.#ops.pop();
    if (op === undefined || op === '(') throw new EvalError('unbalanced parentheses');
    if (op === 'neg') {
      this.#values.push(checked(-this.#pop()));
      return;
    }
    const b = this.#pop();
    const a = this.#pop();
    this.#values.push(applyBinary(op, a, b));
  }

  #topIsReducibleAt(precedence: number): boolean {
    const top = this.#ops.at(-1);
    return top !== undefined && top !== '(' && PRECEDENCE[top] >= precedence;
  }

  run(line: string): bigint {
    let expectOperand = true;
    let i = 0;
    const n = line.length;

    while (i < n) {
      const code = line.charCodeAt(i);
      if (isBlank(code)) {
        i++;
        continue;
      }
      const ch = line[i] as string;

      if (expectOperand) {
        if (isDigit(code)) {
          let j = i + 1;
          while (j < n && isDigit(line.charCodeAt(j))) j++;
          this.#values.push(checked(BigInt(line.slice(i, j))));
          i = j;
          expectOperand = false;
          continue;
        }
        if (ch === '-') this.#ops.push('neg');
        else if (ch === '(') this.#ops.push('(');
        else throw new EvalError(`unexpected '${ch}'`);
      } else if (ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '%') {
        // Left-associative: reduce everything of equal or higher precedence first.
        const precedence = PRECEDENCE[ch];
        while (this.#topIsReducibleAt(precedence)) this.#reduce();
        this.#ops.push(ch);
        expectOperand = true;
      } else if (ch === ')') {
        while (this.#ops.length > 0 && this.#ops.at(-1) !== '(') this.#reduce();
        if (this.#ops.pop() !== '(') throw new EvalError('unbalanced parentheses');
      } else {
        throw new EvalError(`unexpected '${ch}'`);
      }
      i++;
    }

    if (expectOperand) throw new EvalError('missing operand');
    while (this.#ops.length > 0) this.#reduce();
    if (this.#values.length !== 1) throw new EvalError('malformed expression');
    return this.#values[0] as bigint;
  }
}

/** Evaluates one expression; returns `undefined` on any syntax or arithmetic error. */
export function evaluate(line: string): bigint | undefined {
  try {
    return new Evaluator().run(line);
  } catch (e) {
    if (e instanceof EvalError) return undefined;
    throw e;
  }
}

/** Formats the result for one input line, or `null` if the line is blank. */
export function processLine(line: string): string | null {
  if (/^[ \t]*$/.test(line)) return null;
  return evaluate(line)?.toString() ?? 'error';
}
