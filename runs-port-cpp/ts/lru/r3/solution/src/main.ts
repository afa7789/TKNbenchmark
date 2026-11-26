// LRU cache simulator: reads a capacity and a stream of commands from stdin.
import { LruCache } from './lru-cache.ts';

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  // Keys and values are printable ASCII; latin1 maps bytes 1:1 and round-trips any input.
  return Buffer.concat(chunks).toString('latin1');
}

/** Parses the leading decimal digits of `s`; anything after them is ignored. */
function parseCapacity(s: string): number {
  let value = 0;
  for (let i = 0; i < s.length; i++) {
    const digit = s.charCodeAt(i) - 48;
    if (digit < 0 || digit > 9) break;
    value = value * 10 + digit;
  }
  return value;
}

/** Yields each `\n`-terminated line (the last may be unterminated), stripping a trailing `\r`. */
function* lines(data: string): Generator<string> {
  let start = 0;
  while (start < data.length) {
    let end = data.indexOf('\n', start);
    if (end === -1) end = data.length;
    const lineEnd = end > start && data.charCodeAt(end - 1) === 13 ? end - 1 : end;
    yield data.slice(start, lineEnd);
    start = end + 1;
  }
}

/** Returns the `index`-th single-space-delimited token of `line`, or `''` if absent. */
function token(line: string, index: number): string {
  let start = 0;
  for (let i = 0; i < index; i++) {
    const space = line.indexOf(' ', start);
    if (space === -1) return '';
    start = space + 1;
  }
  const end = line.indexOf(' ', start);
  return end === -1 ? line.slice(start) : line.slice(start, end);
}

function run(input: string): string {
  const it = lines(input);
  const first = it.next();
  if (first.done) return '';

  const cache = new LruCache<string, string>(parseCapacity(first.value));
  const out: string[] = [];

  for (const line of it) {
    switch (token(line, 0)) {
      case 'SET':
        cache.set(token(line, 1), token(line, 2));
        break;
      case 'GET':
        out.push(cache.get(token(line, 1)) ?? 'NULL');
        break;
      case 'DEL':
        out.push(cache.delete(token(line, 1)) ? '1' : '0');
        break;
      case 'SIZE':
        out.push(String(cache.size));
        break;
    }
  }

  return out.length === 0 ? '' : out.join('\n') + '\n';
}

const output = run(await readStdin());
if (output.length > 0) process.stdout.write(Buffer.from(output, 'latin1'));
