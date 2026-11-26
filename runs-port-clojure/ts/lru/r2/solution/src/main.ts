/**
 * LRU cache simulator: reads a capacity and a stream of commands from stdin
 * and writes one line of output per GET, DEL and SIZE command.
 */
import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru-cache.ts';

const LINE_BREAK = /\r\n|\r|\n/;

/** Runs one command line against the cache, appending any output to `out`. */
function execute(cache: LruCache, line: string, out: string[]): void {
  const sp1 = line.indexOf(' ');
  const command = sp1 < 0 ? line : line.slice(0, sp1);
  const rest = line.slice(sp1 + 1);
  switch (command) {
    case 'SET': {
      const sp2 = rest.indexOf(' ');
      if (sp2 < 0) throw new Error(`malformed SET command: ${line}`);
      cache.set(rest.slice(0, sp2), rest.slice(sp2 + 1));
      break;
    }
    case 'GET':
      out.push(cache.get(rest) ?? 'NULL');
      break;
    case 'DEL':
      out.push(cache.delete(rest) ? '1' : '0');
      break;
    case 'SIZE':
      out.push(String(cache.size));
      break;
    default:
      // Unknown commands are ignored.
      break;
  }
}

/** Processes the whole input, returning the program's output. */
export function run(input: string): string {
  const lines = input.split(LINE_BREAK);
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
  if (lines.length === 0) return '';

  const capacity = Number.parseInt(lines[0].trim(), 10);
  if (!Number.isSafeInteger(capacity)) throw new Error(`invalid capacity: ${lines[0]}`);
  const cache = new LruCache(capacity);
  const out: string[] = [];
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line !== '') execute(cache, line, out);
  }
  return out.length === 0 ? '' : out.join('\n') + '\n';
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

function main(): void {
  const input = readFileSync(0, 'latin1');
  writeAll(1, Buffer.from(run(input), 'latin1'));
}

main();
