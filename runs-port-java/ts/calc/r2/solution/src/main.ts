/** Reads one expression per line from standard input and prints its value or `error`. */
import { once } from 'node:events'
import { EvaluationError, evaluate, isBlank } from './evaluator.ts'

const NEWLINE = 0x0a

function isBlankLine(src: Uint8Array, start: number, end: number): boolean {
  for (let i = start; i < end; i++) {
    if (!isBlank(src[i]!)) return false
  }
  return true
}

/** Returns the output for one line (including its newline), or '' for a blank line. */
function evaluateLine(src: Uint8Array, start: number, end: number): string {
  if (isBlankLine(src, start, end)) return ''
  try {
    return `${evaluate(src, start, end)}\n`
  } catch (e) {
    if (e instanceof EvaluationError) return 'error\n'
    throw e
  }
}

async function write(text: string): Promise<void> {
  if (text.length > 0 && !process.stdout.write(text)) await once(process.stdout, 'drain')
}

async function main(): Promise<void> {
  // Pieces of a line that spans chunk boundaries; joined once its newline arrives.
  let pending: Buffer[] = []
  const takePending = (tail: Buffer): Buffer => {
    pending.push(tail)
    const line = Buffer.concat(pending)
    pending = []
    return line
  }

  for await (const chunk of process.stdin as AsyncIterable<Buffer>) {
    let output = ''
    let lineStart = 0
    for (let nl = chunk.indexOf(NEWLINE); nl !== -1; nl = chunk.indexOf(NEWLINE, lineStart)) {
      if (pending.length > 0) {
        const line = takePending(chunk.subarray(lineStart, nl))
        output += evaluateLine(line, 0, line.length)
      } else {
        output += evaluateLine(chunk, lineStart, nl)
      }
      lineStart = nl + 1
    }
    if (lineStart < chunk.length) pending.push(chunk.subarray(lineStart))
    await write(output)
  }
  if (pending.length > 0) {
    const line = takePending(Buffer.alloc(0))
    await write(evaluateLine(line, 0, line.length))
  }
}

await main()
