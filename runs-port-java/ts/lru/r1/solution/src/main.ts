/**
 * Reads a capacity followed by cache commands from standard input and writes
 * command results to standard output, one per line.
 */
import { LruCache } from './lru-cache.ts';

const OUTPUT_FLUSH_THRESHOLD = 1 << 16;

/** Buffers output lines and hands them to the sink in large chunks. */
class LineWriter {
  readonly #sink: (chunk: string) => void;
  #lines: string[] = [];
  #pending = 0;

  constructor(sink: (chunk: string) => void) {
    this.#sink = sink;
  }

  writeLine(text: string): void {
    this.#lines.push(text);
    this.#pending += text.length + 1;
    if (this.#pending >= OUTPUT_FLUSH_THRESHOLD) this.flush();
  }

  flush(): void {
    if (this.#lines.length === 0) return;
    this.#lines.push('');
    this.#sink(this.#lines.join('\n'));
    this.#lines = [];
    this.#pending = 0;
  }
}

/** Interprets the command stream: a capacity header, then one command per line. */
class CommandProcessor {
  readonly #out: LineWriter;
  #cache: LruCache<string, string> | null = null;

  constructor(out: LineWriter) {
    this.#out = out;
  }

  processLine(rawLine: string): void {
    const line = rawLine.endsWith('\r') ? rawLine.slice(0, -1) : rawLine;
    if (this.#cache === null) {
      this.#cache = new LruCache(parseCapacity(line));
      return;
    }
    this.#execute(this.#cache, line);
  }

  #execute(cache: LruCache<string, string>, line: string): void {
    const firstSpace = line.indexOf(' ');
    const command = firstSpace < 0 ? line : line.slice(0, firstSpace);
    switch (command) {
      case 'SET': {
        const secondSpace = line.indexOf(' ', firstSpace + 1);
        if (secondSpace < 0) return;
        cache.set(line.slice(firstSpace + 1, secondSpace), line.slice(secondSpace + 1));
        break;
      }
      case 'GET': {
        if (firstSpace < 0) return;
        this.#out.writeLine(cache.get(line.slice(firstSpace + 1)) ?? 'NULL');
        break;
      }
      case 'DEL': {
        if (firstSpace < 0) return;
        this.#out.writeLine(cache.delete(line.slice(firstSpace + 1)) ? '1' : '0');
        break;
      }
      case 'SIZE':
        this.#out.writeLine(String(cache.size));
        break;
      default:
        // Blank or unrecognised lines are ignored.
        break;
    }
  }
}

function parseCapacity(header: string): number {
  const text = header.trim();
  if (!/^[+-]?\d+$/.test(text)) throw new Error(`invalid capacity: ${JSON.stringify(header)}`);
  return Number.parseInt(text, 10);
}

async function main(): Promise<void> {
  const out = new LineWriter((chunk) => process.stdout.write(chunk, 'latin1'));
  const processor = new CommandProcessor(out);

  process.stdin.setEncoding('latin1');
  let carry = '';
  for await (const chunk of process.stdin as AsyncIterable<string>) {
    const text = carry + chunk;
    let start = 0;
    let end: number;
    while ((end = text.indexOf('\n', start)) >= 0) {
      processor.processLine(text.slice(start, end));
      start = end + 1;
    }
    carry = text.slice(start);
  }
  if (carry.length > 0) processor.processLine(carry);
  out.flush();
}

await main();
