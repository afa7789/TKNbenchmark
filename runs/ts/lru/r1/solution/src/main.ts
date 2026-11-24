import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru.ts';

const OUTPUT_FLUSH_THRESHOLD = 1 << 16;

class OutputBuffer {
  #parts: string[] = [];
  #length = 0;

  push(line: string): void {
    this.#parts.push(line);
    this.#length += line.length + 1;
    if (this.#length >= OUTPUT_FLUSH_THRESHOLD) this.flush();
  }

  flush(): void {
    if (this.#parts.length === 0) return;
    writeAll(this.#parts.join('\n') + '\n');
    this.#parts = [];
    this.#length = 0;
  }
}

function writeAll(text: string): void {
  const buf = Buffer.from(text, 'latin1');
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(1, buf, offset, buf.length - offset);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'EAGAIN') continue;
      throw err;
    }
  }
}

function stripCr(line: string): string {
  return line.endsWith('\r') ? line.slice(0, -1) : line;
}

function run(input: string): void {
  const out = new OutputBuffer();
  let pos = 0;

  const nextLine = (): string | undefined => {
    if (pos >= input.length) return undefined;
    let end = input.indexOf('\n', pos);
    if (end === -1) end = input.length;
    const line = stripCr(input.slice(pos, end));
    pos = end + 1;
    return line;
  };

  const header = nextLine();
  if (header === undefined) return;
  const capacity = Number.parseInt(header.trim(), 10);
  const cache = new LruCache<string, string>(capacity);

  for (let line = nextLine(); line !== undefined; line = nextLine()) {
    if (line.length === 0) continue;
    const first = line.indexOf(' ');
    const command = first === -1 ? line : line.slice(0, first);

    switch (command) {
      case 'SET': {
        const second = line.indexOf(' ', first + 1);
        if (second === -1) break;
        cache.set(line.slice(first + 1, second), line.slice(second + 1));
        break;
      }
      case 'GET':
        out.push(cache.get(line.slice(first + 1)) ?? 'NULL');
        break;
      case 'DEL':
        out.push(cache.delete(line.slice(first + 1)) ? '1' : '0');
        break;
      case 'SIZE':
        out.push(String(cache.size));
        break;
      default:
        // Unknown commands are ignored; the spec defines no output for them.
        break;
    }
  }

  out.flush();
}

run(readFileSync(0, 'latin1'));
