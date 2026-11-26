import { lineResult } from './calc.ts';

const FLUSH_THRESHOLD = 1 << 16;

/** Reads stdin line by line (split on '\n' only) and writes one result per non-blank line. */
async function run(): Promise<void> {
  process.stdin.setEncoding('latin1');

  let pending = '';
  let out: string[] = [];
  let outSize = 0;

  const flush = async (): Promise<void> => {
    if (out.length === 0) return;
    const chunk = out.join('');
    out = [];
    outSize = 0;
    if (!process.stdout.write(chunk, 'latin1')) {
      await new Promise<void>((resolve) => process.stdout.once('drain', resolve));
    }
  };

  const emit = (line: string): void => {
    const result = lineResult(line);
    if (result === null) return;
    out.push(result, '\n');
    outSize += result.length + 1;
  };

  for await (const chunk of process.stdin as AsyncIterable<string>) {
    const data = pending + chunk;
    let start = 0;
    let nl: number;
    while ((nl = data.indexOf('\n', start)) !== -1) {
      emit(data.slice(start, nl));
      start = nl + 1;
    }
    pending = data.slice(start);
    if (outSize >= FLUSH_THRESHOLD) await flush();
  }
  if (pending.length > 0) emit(pending);
  await flush();
}

await run();
process.exitCode = 0;
