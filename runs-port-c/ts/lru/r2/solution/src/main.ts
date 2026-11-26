/**
 * lru — simulate an LRU cache driven by commands on standard input.
 *
 * Line 1 holds the capacity; each later line is one of
 * `SET <key> <value>`, `GET <key>`, `DEL <key>` or `SIZE`.
 * Unknown or malformed commands are ignored.
 */
import { LruCache } from './lru-cache.ts';

const MAX_CAPACITY = 0xffff_ffff;

/** Parses the capacity line leniently: leading blanks, then digits; clamped to [1, 2^32 - 1]. */
function parseCapacity(line: string): number {
  const digits = /^[ \t]*(\d*)/.exec(line)?.[1] ?? '';
  let value = 0;
  for (const ch of digits) {
    value = Math.min(value * 10 + (ch.charCodeAt(0) - 48), MAX_CAPACITY);
  }
  return Math.max(value, 1);
}

/** Splits a line on spaces, discarding empty tokens produced by repeated spaces. */
function tokenize(line: string): string[] {
  const tokens = line.split(' ');
  return tokens.includes('') ? tokens.filter((t) => t !== '') : tokens;
}

export function run(input: string): string {
  const lines = input.split('\n');
  const cache = new LruCache<string, string>(parseCapacity(lines[0] ?? ''));
  const out: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i];
    if (line.endsWith('\r')) line = line.slice(0, -1);
    const [cmd, key = '', value = ''] = tokenize(line);

    switch (cmd) {
      case 'SET':
        if (key !== '') cache.set(key, value);
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
    }
  }

  return out.length > 0 ? out.join('\n') + '\n' : '';
}

async function readStdin(): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks);
}

// Keys and values are arbitrary bytes compared byte-for-byte; latin1 maps each byte to one char.
const output = run((await readStdin()).toString('latin1'));
process.stdout.write(Buffer.from(output, 'latin1'));
