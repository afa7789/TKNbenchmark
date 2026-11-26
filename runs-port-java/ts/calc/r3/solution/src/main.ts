/**
 * Entry point: reads one expression per line from standard input and prints
 * its value or `error`. Blank lines produce no output.
 */
import { readFileSync, writeSync } from 'node:fs'
import { CalcError } from './calc-error.ts'
import { evaluate, isBlank } from './evaluator.ts'

function evaluateLine(line: string): string {
  try {
    return evaluate(line).toString()
  } catch (e) {
    if (e instanceof CalcError) return 'error'
    throw e
  }
}

function writeAll(fd: number, data: Buffer): void {
  let offset = 0
  while (offset < data.length) {
    try {
      offset += writeSync(fd, data, offset)
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'EAGAIN') continue
      throw e
    }
  }
}

function main(): void {
  // latin1 maps every byte to one char, so arbitrary input never fails decoding;
  // any non-ASCII byte (and '\r') is simply an invalid token.
  const input = readFileSync(0).toString('latin1')
  const out: string[] = []
  for (const line of input.split('\n')) {
    if (!isBlank(line)) out.push(evaluateLine(line), '\n')
  }
  writeAll(1, Buffer.from(out.join(''), 'latin1'))
}

main()
