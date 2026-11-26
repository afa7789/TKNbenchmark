import { evaluate, EvalError } from './evaluate.ts';

/** Maximum number of buffered result lines before writing to stdout. */
const FLUSH_THRESHOLD = 4096;

/** Result text for one input line, or `null` if the line produces no output. */
function evaluateLine(line: string): string | null {
  try {
    const value = evaluate(line);
    return value === null ? null : value.toString();
  } catch (err) {
    if (err instanceof EvalError) return 'error';
    throw err;
  }
}

function main(): void {
  const out: string[] = [];
  let pending = '';

  const flush = (): void => {
    if (out.length === 0) return;
    process.stdout.write(out.join('\n') + '\n');
    out.length = 0;
  };

  const processLines = (lines: string[]): void => {
    for (const line of lines) {
      const result = evaluateLine(line);
      if (result !== null) out.push(result);
    }
    if (out.length >= FLUSH_THRESHOLD) flush();
  };

  // latin1 maps every byte to one code unit, so stray non-ASCII bytes are
  // simply rejected as unexpected characters.
  process.stdin.setEncoding('latin1');
  process.stdin.on('data', (chunk: string) => {
    const lines = (pending + chunk).split('\n');
    pending = lines.pop() ?? '';
    processLines(lines);
  });
  process.stdin.on('end', () => {
    if (pending !== '') processLines([pending]);
    pending = '';
    flush();
    process.exitCode = 0;
  });
}

main();
