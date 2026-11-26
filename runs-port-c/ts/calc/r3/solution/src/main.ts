/**
 * Reads one expression per line from standard input and prints its value or
 * "error". Blank lines (only spaces/tabs) produce no output.
 */
import { evaluate, isBlank } from "./calc.ts";

const NEWLINE = 0x0a;
const FLUSH_THRESHOLD = 1 << 16;

class Output {
  private parts: string[] = [];
  private size = 0;

  write(line: string): void {
    this.parts.push(line);
    this.size += line.length;
    if (this.size >= FLUSH_THRESHOLD) this.flush();
  }

  flush(): void {
    if (this.parts.length === 0) return;
    process.stdout.write(this.parts.join(""));
    this.parts = [];
    this.size = 0;
  }
}

function isBlankLine(line: Uint8Array): boolean {
  return line.every(isBlank);
}

function processLine(line: Uint8Array, out: Output): void {
  if (isBlankLine(line)) return;
  const value = evaluate(line);
  out.write(value === null ? "error\n" : `${value}\n`);
}

async function main(): Promise<void> {
  const out = new Output();
  // Bytes of a line not yet terminated by '\n', possibly spanning chunks.
  let pending: Buffer[] = [];

  for await (const chunk of process.stdin as AsyncIterable<Buffer>) {
    let start = 0;
    let nl: number;
    while ((nl = chunk.indexOf(NEWLINE, start)) !== -1) {
      const piece = chunk.subarray(start, nl);
      if (pending.length > 0) {
        pending.push(piece);
        processLine(Buffer.concat(pending), out);
        pending = [];
      } else {
        processLine(piece, out);
      }
      start = nl + 1;
    }
    if (start < chunk.length) pending.push(chunk.subarray(start));
  }
  if (pending.length > 0) processLine(Buffer.concat(pending), out);
  out.flush();
}

await main();
