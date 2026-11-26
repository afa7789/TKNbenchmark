/** Reads LRU cache commands from standard input and writes results to standard output. */
import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru-cache.ts';

const LINE_BREAK = /\r\n|\r|\n/;

/** Executes one command line, returning its output line or `undefined` if it produces none. */
function execute(cache: LruCache<string, string>, line: string): string | undefined {
  const firstSpace = line.indexOf(' ');
  const command = firstSpace < 0 ? line : line.slice(0, firstSpace);
  switch (command) {
    case 'SET': {
      if (firstSpace < 0) return undefined;
      const secondSpace = line.indexOf(' ', firstSpace + 1);
      if (secondSpace < 0) return undefined;
      cache.set(line.slice(firstSpace + 1, secondSpace), line.slice(secondSpace + 1));
      return undefined;
    }
    case 'GET':
      if (firstSpace < 0) return undefined;
      return cache.get(line.slice(firstSpace + 1)) ?? 'NULL';
    case 'DEL':
      if (firstSpace < 0) return undefined;
      return cache.delete(line.slice(firstSpace + 1)) ? '1' : '0';
    case 'SIZE':
      return String(cache.size);
    default:
      // Blank or unrecognised lines are ignored.
      return undefined;
  }
}

/** Runs the simulation over the whole input text and returns the output text. */
export function run(input: string): string {
  const lines = input.split(LINE_BREAK);
  // A trailing line break does not start another line.
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
  if (lines.length === 0) return '';

  const capacity = Number.parseInt(lines[0].trim(), 10);
  const cache = new LruCache<string, string>(capacity);
  const output: string[] = [];
  for (let i = 1; i < lines.length; i++) {
    const result = execute(cache, lines[i]);
    if (result !== undefined) output.push(result);
  }
  return output.length > 0 ? output.join('\n') + '\n' : '';
}

function writeAll(fd: number, data: Buffer): void {
  let offset = 0;
  while (offset < data.length) {
    offset += writeSync(fd, data, offset, data.length - offset);
  }
}

function main(): void {
  const input = readFileSync(0, 'latin1');
  writeAll(1, Buffer.from(run(input), 'latin1'));
}

main();
