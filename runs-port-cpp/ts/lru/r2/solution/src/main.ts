// LRU cache simulator: reads a capacity and a stream of commands from stdin
// and writes command results to stdout. See SPEC.md.

import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru-cache.ts';

/** Splits `line` on runs of spaces, ignoring leading and trailing ones. */
function tokenize(line: string): string[] {
  return line.split(' ').filter((token) => token !== '');
}

/** Parses the leading decimal digits of the first token; anything else yields 0. */
function parseCapacity(line: string): number {
  const match = /^\d+/.exec(tokenize(line)[0] ?? '');
  if (!match) return 0;
  const value = Number(match[0]);
  return Number.isSafeInteger(value) ? value : 0;
}

/** Runs one command line, appending any output lines to `out`. */
function execute(cache: LruCache, line: string, out: string[]): void {
  const [command, key = '', value = ''] = tokenize(line);
  switch (command) {
    case 'SET':
      if (key !== '' && value !== '') cache.set(key, value);
      break;
    case 'GET':
      out.push(cache.get(key) ?? 'NULL');
      break;
    case 'DEL':
      out.push(cache.delete(key) ? '1' : '0');
      break;
    case 'SIZE':
      out.push(String(cache.size));
      break;
    default:
    // Blank or unrecognised lines produce no output.
  }
}

function writeAll(fd: number, data: Buffer): void {
  let offset = 0;
  while (offset < data.length) {
    try {
      offset += writeSync(fd, data, offset);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'EAGAIN') throw error;
    }
  }
}

function main(): void {
  // latin1 maps bytes 1:1 to UTF-16 code units, so arbitrary input round-trips.
  const input = readFileSync(0, 'latin1');
  if (input === '') return;

  const lines = input.split('\n');
  if (lines.at(-1) === '') lines.pop();
  const stripCr = (line: string): string => (line.endsWith('\r') ? line.slice(0, -1) : line);

  const cache = new LruCache(parseCapacity(stripCr(lines[0])));
  const out: string[] = [];
  for (let i = 1; i < lines.length; i++) {
    execute(cache, stripCr(lines[i]), out);
  }

  if (out.length > 0) {
    writeAll(1, Buffer.from(out.join('\n') + '\n', 'latin1'));
  }
}

main();
