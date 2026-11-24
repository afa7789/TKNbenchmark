'use strict'

const { evaluate, EvalError } = require('./evaluate.js')

function evaluateLine(line) {
  try {
    const value = evaluate(line)
    return value === null ? null : value.toString()
  } catch (err) {
    if (err instanceof EvalError) return 'error'
    throw err
  }
}

function main() {
  const out = []
  let pending = ''

  const processLines = (text, final) => {
    const lines = text.split('\n')
    pending = final ? '' : lines.pop()
    for (const line of lines) {
      const result = evaluateLine(line)
      if (result !== null) out.push(result)
    }
    if (out.length >= 4096) flush()
  }

  const flush = () => {
    if (out.length === 0) return
    process.stdout.write(out.join('\n') + '\n')
    out.length = 0
  }

  process.stdin.setEncoding('latin1')
  process.stdin.on('data', (chunk) => processLines(pending + chunk, false))
  process.stdin.on('end', () => {
    if (pending !== '') processLines(pending, true)
    flush()
    process.exitCode = 0
  })
}

main()
