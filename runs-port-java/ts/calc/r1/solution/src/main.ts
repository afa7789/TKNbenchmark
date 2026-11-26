/**
 * Command-line entry point: evaluates one expression per line of standard input
 * and prints its value, or `error`.
 */
import { evaluate, isBlank } from './evaluator.ts';

const NEWLINE = 0x0a;
const FLUSH_THRESHOLD = 1 << 16;

class Output {
  private parts: string[] = [];
  private size = 0;

  line(text: string): void {
    this.parts.push(text);
    this.size += text.length + 1;
    if (this.size >= FLUSH_THRESHOLD) this.flush();
  }

  flush(): void {
    if (this.parts.length === 0) return;
    process.stdout.write(this.parts.join('\n') + '\n');
    this.parts = [];
    this.size = 0;
  }
}

function emit(buf: Uint8Array, start: number, end: number, out: Output): void {
  if (isBlank(buf, start, end)) return;
  const value = evaluate(buf, start, end);
  out.line(value === undefined ? 'error' : value.toString());
}

async function main(): Promise<void> {
  const out = new Output();
  // Pieces of a line that is still incomplete at the end of the last chunk.
  let pending: Buffer[] = [];

  for await (const chunk of process.stdin as AsyncIterable<Buffer>) {
    let start = 0;
    let nl = chunk.indexOf(NEWLINE);
    if (nl !== -1 && pending.length > 0) {
      pending.push(chunk.subarray(0, nl));
      const line = Buffer.concat(pending);
      pending = [];
      emit(line, 0, line.length, out);
      start = nl + 1;
      nl = chunk.indexOf(NEWLINE, start);
    }
    while (nl !== -1) {
      emit(chunk, start, nl, out);
      start = nl + 1;
      nl = chunk.indexOf(NEWLINE, start);
    }
    if (start < chunk.length) pending.push(chunk.subarray(start));
  }
  if (pending.length > 0) {
    const line = Buffer.concat(pending);
    emit(line, 0, line.length, out);
  }
  out.flush();
}

main().catch((err: unknown) => {
  process.stderr.write(`calc: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exitCode = 1;
});
