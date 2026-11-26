import { readFileSync, writeSync } from 'node:fs'
import { LRUCache } from './lru.ts'

function writeAll(fd: number, data: string): void {
  const buf = Buffer.from(data)
  let off = 0
  while (off < buf.length) {
    try {
      off += writeSync(fd, buf, off)
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'EAGAIN') throw err
    }
  }
}

/** Executes the command script (first line: capacity) and returns the output lines. */
export function run(input: string): string[] {
  const lines = input.split('\n')
  const capacity = Number.parseInt(lines[0] ?? '', 10)
  const cache = new LRUCache<string, string>(capacity)
  const out: string[] = []

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i]!
    if (line.endsWith('\r')) line = line.slice(0, -1)
    if (line === '') continue
    const sp1 = line.indexOf(' ')
    const cmd = sp1 === -1 ? line : line.slice(0, sp1)
    switch (cmd) {
      case 'SET': {
        const sp2 = line.indexOf(' ', sp1 + 1)
        cache.set(line.slice(sp1 + 1, sp2), line.slice(sp2 + 1))
        break
      }
      case 'GET':
        out.push(cache.get(line.slice(sp1 + 1)) ?? 'NULL')
        break
      case 'DEL':
        out.push(cache.delete(line.slice(sp1 + 1)) ? '1' : '0')
        break
      case 'SIZE':
        out.push(String(cache.size))
        break
      default:
        break // ignore unknown commands
    }
  }
  return out
}

function main(): void {
  const out = run(readFileSync(0, 'latin1'))
  if (out.length > 0) writeAll(1, out.join('\n') + '\n')
}

main()
