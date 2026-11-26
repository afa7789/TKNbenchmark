/** Reads LRU cache commands from standard input and writes results to standard output. */
import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru-cache.ts';

/** Iterates the lines of a text, tolerating a trailing `\r` and a missing final newline. */
function* lines(text: string): Generator<string> {
  let pos = 0;
  while (pos < text.length) {
    let end = text.indexOf('\n', pos);
    if (end < 0) end = text.length;
    const line = text.charCodeAt(end - 1) === 13 && end > pos ? text.slice(pos, end - 1) : text.slice(pos, end);
    pos = end + 1;
    yield line;
  }
}

function parseCapacity(line: string): number {
  const text = line.trim();
  if (!/^[+-]?\d+$/.test(text)) throw new Error(`invalid capacity: ${JSON.stringify(text)}`);
  return Number(text);
}

/** Executes one command, appending any output line to `out`. Unknown or malformed lines are ignored. */
function execute(cache: LruCache<string>, line: string, out: string[]): void {
  const firstSpace = line.indexOf(' ');
  const command = firstSpace < 0 ? line : line.slice(0, firstSpace);
  switch (command) {
    case 'SET': {
      if (firstSpace < 0) return;
      const secondSpace = line.indexOf(' ', firstSpace + 1);
      if (secondSpace < 0) return;
      cache.set(line.slice(firstSpace + 1, secondSpace), line.slice(secondSpace + 1));
      return;
    }
    case 'GET':
      if (firstSpace < 0) return;
      out.push(cache.get(line.slice(firstSpace + 1)) ?? 'NULL');
      return;
    case 'DEL':
      if (firstSpace < 0) return;
      out.push(cache.delete(line.slice(firstSpace + 1)) ? '1' : '0');
      return;
    case 'SIZE':
      out.push(String(cache.size));
      return;
  }
}

export function run(input: string): string {
  const it = lines(input);
  let first = it.next();
  while (!first.done && first.value.trim() === '') first = it.next();
  if (first.done) return '';

  const cache = new LruCache<string>(parseCapacity(first.value));
  const out: string[] = [];
  for (const line of it) execute(cache, line, out);
  return out.length > 0 ? out.join('\n') + '\n' : '';
}

function writeAll(fd: number, data: Buffer): void {
  let offset = 0;
  while (offset < data.length) {
    try {
      offset += writeSync(fd, data, offset);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'EAGAIN') throw err;
    }
  }
}

const input = readFileSync(0).toString('latin1');
writeAll(1, Buffer.from(run(input), 'latin1'));
