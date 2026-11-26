import { evalLine } from './calc.ts';

// '\r' also ends a line; any empty piece it leaves behind is a blank line.
const LINE_BREAK = /\r\n?|\n/;
const FLUSH_THRESHOLD = 1 << 16;

async function main(): Promise<void> {
  process.stdin.setEncoding('latin1');
  let pending = '';
  let out: string[] = [];
  let outSize = 0;

  const flush = (): void => {
    if (out.length > 0) process.stdout.write(out.join(''));
    out = [];
    outSize = 0;
  };

  const handle = (line: string): void => {
    const result = evalLine(line);
    if (result === null) return;
    out.push(result, '\n');
    outSize += result.length + 1;
    if (outSize >= FLUSH_THRESHOLD) flush();
  };

  for await (const chunk of process.stdin as AsyncIterable<string>) {
    const lines = (pending + chunk).split(LINE_BREAK);
    pending = lines.pop()!;
    for (const line of lines) handle(line);
  }
  if (pending !== '') handle(pending);
  flush();
}

await main();
