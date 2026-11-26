/**
 * LRU cache simulator driven by commands on standard input (see SPEC.md).
 *
 * Input is decoded as latin1 so arbitrary bytes round-trip unchanged.
 */
import { LruCache } from './lru.ts'

const MAX_CAPACITY_DIGITS = 18

/** Split a line into space-separated tokens, ignoring repeated spaces. */
function tokenize(line: string): string[] {
  return line.split(' ').filter((token) => token !== '')
}

/** Parse the capacity line; returns undefined if it is not a positive integer. */
function parseCapacity(line: string): number | undefined {
  const [token] = tokenize(line)
  if (token === undefined || token.length > MAX_CAPACITY_DIGITS || !/^\d+$/.test(token)) {
    return undefined
  }
  const capacity = Number(token)
  return capacity > 0 ? capacity : undefined
}

/** Execute one command line, appending any output lines to `out`. */
function runCommand(cache: LruCache<string>, line: string, out: string[]): void {
  const [command, key, value] = tokenize(line)
  switch (command) {
    case 'GET':
      if (key !== undefined) out.push(cache.get(key) ?? 'NULL')
      break
    case 'SET':
      if (key !== undefined && value !== undefined) cache.set(key, value)
      break
    case 'DEL':
      if (key !== undefined) out.push(cache.delete(key) ? '1' : '0')
      break
    case 'SIZE':
      out.push(String(cache.size))
      break
    default:
      // Blank lines and unknown commands are ignored.
      break
  }
}

/** Read all of standard input (works for pipes, files and non-blocking fds). */
async function readStdin(): Promise<string> {
  const chunks: Buffer[] = []
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer)
  return Buffer.concat(chunks).toString('latin1')
}

async function main(): Promise<void> {
  const input = await readStdin()
  if (input.length === 0) return

  const lines = input.split('\n')
  if (lines.at(-1) === '') lines.pop()

  const capacity = parseCapacity(stripCarriageReturn(lines[0] ?? ''))
  if (capacity === undefined) return // nothing to simulate

  const cache = new LruCache<string>(capacity)
  const out: string[] = []
  for (let i = 1; i < lines.length; i++) {
    runCommand(cache, stripCarriageReturn(lines[i]!), out)
  }

  if (out.length > 0) {
    process.stdout.write(Buffer.from(out.join('\n') + '\n', 'latin1'))
  }
}

function stripCarriageReturn(line: string): string {
  return line.endsWith('\r') ? line.slice(0, -1) : line
}

await main()
