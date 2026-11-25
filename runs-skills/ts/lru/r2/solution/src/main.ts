import { readFileSync, writeSync } from 'node:fs';
import { LruCache } from './lru.ts';

/** Runs the command script in `input` and returns the output lines. */
export function run(input: string): string[] {
  const out: string[] = [];
  let cache: LruCache | undefined;
  let pos = 0;
  const end = input.length;

  while (pos < end) {
    let eol = input.indexOf('\n', pos);
    if (eol < 0) eol = end;
    let lineEnd = eol;
    if (lineEnd > pos && input.charCodeAt(lineEnd - 1) === 13 /* \r */) lineEnd--;
    const line = input.slice(pos, lineEnd);
    pos = eol + 1;
    if (line.length === 0) continue;

    if (cache === undefined) {
      cache = new LruCache(Number.parseInt(line, 10));
      continue;
    }

    const sp1 = line.indexOf(' ');
    const cmd = sp1 < 0 ? line : line.slice(0, sp1);
    switch (cmd) {
      case 'SET': {
        const sp2 = line.indexOf(' ', sp1 + 1);
        if (sp2 < 0) break;
        cache.set(line.slice(sp1 + 1, sp2), line.slice(sp2 + 1));
        break;
      }
      case 'GET':
        if (sp1 >= 0) out.push(cache.get(line.slice(sp1 + 1)) ?? 'NULL');
        break;
      case 'DEL':
        if (sp1 >= 0) out.push(cache.delete(line.slice(sp1 + 1)) ? '1' : '0');
        break;
      case 'SIZE':
        out.push(String(cache.size));
        break;
      default:
        break;
    }
  }
  return out;
}

function writeAll(fd: number, data: Buffer): void {
  let offset = 0;
  while (offset < data.length) {
    try {
      offset += writeSync(fd, data, offset);
    } catch (e) {
      if (Error.isError(e) && (e as NodeJS.ErrnoException).code === 'EAGAIN') continue;
      throw e;
    }
  }
}

if (import.meta.main) {
  const input = readFileSync(0).toString('latin1');
  const lines = run(input);
  if (lines.length > 0) writeAll(1, Buffer.from(lines.join('\n') + '\n', 'latin1'));
}
