/**
 * 64-bit signed integer expression evaluator.
 *
 * Reads one expression per line from standard input and prints its value,
 * or `error` for syntax errors, division by zero, and 64-bit overflow.
 */

const INT_MIN = -(1n << 63n);
const INT_MAX = (1n << 63n) - 1n;

const CH_TAB = 0x09;
const CH_NEWLINE = 0x0a;
const CH_SPACE = 0x20;
const CH_0 = 0x30;
const CH_9 = 0x39;

/** Raised for any syntax, domain, or overflow error in an expression. */
export class CalcError extends Error {
  override name = 'CalcError';
}

type BinaryOp = '+' | '-' | '*' | '/' | '%';
type StackOp = BinaryOp | 'neg' | '(';

type Token =
  | { kind: 'number'; value: bigint }
  | { kind: 'op'; op: BinaryOp | '(' | ')' };

const PRECEDENCE: Readonly<Record<StackOp, number>> = {
  '(': 0,
  '+': 1,
  '-': 1,
  '*': 2,
  '/': 2,
  '%': 2,
  // Unary minus binds tighter than every binary operator.
  neg: 3,
};

const OPERATORS: ReadonlyMap<number, BinaryOp | '(' | ')'> = new Map(
  (['+', '-', '*', '/', '%', '(', ')'] as const).map((op) => [op.charCodeAt(0), op]),
);

function isBlank(byte: number): boolean {
  return byte === CH_SPACE || byte === CH_TAB;
}

function isDigit(byte: number): boolean {
  return byte >= CH_0 && byte <= CH_9;
}

function check(value: bigint): bigint {
  if (value < INT_MIN || value > INT_MAX) {
    throw new CalcError('overflow');
  }
  return value;
}

function applyBinary(op: BinaryOp, a: bigint, b: bigint): bigint {
  switch (op) {
    case '+':
      return check(a + b);
    case '-':
      return check(a - b);
    case '*':
      return check(a * b);
    case '/':
      if (b === 0n) throw new CalcError('division by zero');
      // BigInt division already truncates toward zero.
      return check(a / b);
    case '%':
      if (b === 0n) throw new CalcError('division by zero');
      // The remainder takes the dividend's sign and always fits (INT_MIN % -1 == 0).
      return a % b;
  }
}

/** Yields the tokens of `line[start, end)`; invalid characters raise CalcError. */
function* tokens(line: Uint8Array, start: number, end: number): Generator<Token> {
  let pos = start;
  while (pos < end) {
    const byte = line[pos];
    if (isBlank(byte)) {
      pos++;
    } else if (isDigit(byte)) {
      const begin = pos;
      while (pos < end && isDigit(line[pos])) pos++;
      const value = BigInt(Buffer.from(line.buffer, line.byteOffset + begin, pos - begin).toString('latin1'));
      yield { kind: 'number', value };
    } else {
      const op = OPERATORS.get(byte);
      if (op === undefined) throw new CalcError('invalid character');
      pos++;
      yield { kind: 'op', op };
    }
  }
}

/**
 * Evaluates the expression in `line[start, end)` and returns its value.
 *
 * Uses an operator-precedence (shunting-yard) evaluator so that deeply
 * nested input cannot exhaust the call stack.
 */
export function evaluate(line: Uint8Array, start = 0, end = line.length): bigint {
  const values: bigint[] = [];
  const ops: StackOp[] = [];

  const reduceTop = (): void => {
    const op = ops.pop();
    if (op === 'neg') {
      values.push(check(-values.pop()!));
    } else if (op !== undefined && op !== '(') {
      const b = values.pop()!;
      const a = values.pop()!;
      values.push(applyBinary(op, a, b));
    }
  };

  let expectOperand = true;
  for (const token of tokens(line, start, end)) {
    if (expectOperand) {
      if (token.kind === 'number') {
        if (token.value > INT_MAX) throw new CalcError('literal out of range');
        values.push(token.value);
        expectOperand = false;
      } else if (token.op === '-') {
        ops.push('neg');
      } else if (token.op === '(') {
        ops.push('(');
      } else {
        throw new CalcError('expected operand');
      }
    } else if (token.kind === 'number' || token.op === '(') {
      throw new CalcError('expected operator');
    } else if (token.op === ')') {
      while (ops.length > 0 && ops[ops.length - 1] !== '(') reduceTop();
      if (ops.length === 0) throw new CalcError("unbalanced ')'");
      ops.pop();
    } else {
      const prec = PRECEDENCE[token.op];
      // Left-associative: reduce operators of equal or higher precedence.
      while (ops.length > 0 && PRECEDENCE[ops[ops.length - 1]] >= prec) reduceTop();
      ops.push(token.op);
      expectOperand = true;
    }
  }

  if (expectOperand) throw new CalcError('missing operand');
  while (ops.length > 0) {
    if (ops[ops.length - 1] === '(') throw new CalcError("unbalanced '('");
    reduceTop();
  }
  return values[0];
}

/** Returns one output line per non-blank line of `input`. */
export function* processInput(input: Uint8Array): Generator<string> {
  let start = 0;
  while (start < input.length) {
    let end = input.indexOf(CH_NEWLINE, start);
    if (end < 0) end = input.length;
    const next = end + 1;

    let first = start;
    while (first < end && isBlank(input[first])) first++;
    if (first < end) {
      try {
        yield evaluate(input, first, end).toString();
      } catch (err) {
        if (!(err instanceof CalcError)) throw err;
        yield 'error';
      }
    }
    start = next;
  }
}

/** Reads all of standard input; streaming avoids EAGAIN on non-blocking pipes. */
async function readStdin(): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks);
}

async function main(): Promise<number> {
  const input = await readStdin();
  const out: string[] = [];
  for (const result of processInput(input)) out.push(result, '\n');
  process.stdout.write(out.join(''));
  return 0;
}

process.exitCode = await main();
