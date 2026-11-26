/**
 * lru — simulate an LRU cache driven by commands on standard input.
 *
 * Input is read in full and decoded as latin1 so every byte maps to exactly one
 * code unit; output is encoded the same way, preserving arbitrary bytes.
 */
import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru-cache.ts';

const MIN_CAPACITY = 1;
const MAX_CAPACITY = 1_000_000;
/** Keys and values longer than this are rejected (and the command ignored). */
const MAX_TOKEN_LENGTH = 255;
/** Only this many leading bytes of the capacity line are considered. */
const CAPACITY_FIELD_WIDTH = 31;

/**
 * Parses the capacity line the way C's `strtol` would: optional leading
 * whitespace, optional sign, then decimal digits; anything else stops the
 * scan. The result is clamped into the supported range.
 */
function parseCapacity(line: string): number {
  const match = /^[ \t\n\v\f\r]*([+-]?)(\d*)/.exec(line.slice(0, CAPACITY_FIELD_WIDTH));
  const digits = match?.[2] ?? '';
  if (digits === '') return MIN_CAPACITY;
  const value = Number(digits) * (match?.[1] === '-' ? -1 : 1);
  return Math.min(MAX_CAPACITY, Math.max(MIN_CAPACITY, value));
}

/** Splits a line into space-separated tokens; runs of spaces count as one separator. */
function tokenize(line: string): string[] {
  return line.split(' ').filter((token) => token !== '');
}

function stripCarriageReturn(line: string): string {
  return line.endsWith('\r') ? line.slice(0, -1) : line;
}

function runCommand(cache: LruCache<string, string>, line: string, output: string[]): void {
  const [command, key, value] = tokenize(line);
  if (command === undefined) return;

  if (command === 'SIZE') {
    output.push(String(cache.size));
    return;
  }
  if (key === undefined || key.length > MAX_TOKEN_LENGTH) return;

  switch (command) {
    case 'GET':
      output.push(cache.get(key) ?? 'NULL');
      break;
    case 'DEL':
      output.push(cache.delete(key) ? '1' : '0');
      break;
    case 'SET':
      if (value !== undefined && value.length <= MAX_TOKEN_LENGTH) cache.set(key, value);
      break;
    default:
      // Unknown commands are ignored.
      break;
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
  const input = readFileSync(0).toString('latin1');
  if (input === '') return;

  const lines = input.split('\n');
  const cache = new LruCache<string, string>(parseCapacity(stripCarriageReturn(lines[0])));
  const output: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    runCommand(cache, stripCarriageReturn(lines[i]), output);
  }

  if (output.length > 0) {
    writeAll(1, Buffer.from(output.join('\n') + '\n', 'latin1'));
  }
}

main();
