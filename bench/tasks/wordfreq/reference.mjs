import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const isLetter = (c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
const byWord = (a, b) => (a < b ? -1 : a > b ? 1 : 0)

export function solve(buf) {
  const counts = new Map()
  let start = -1
  for (let i = 0; i <= buf.length; i++) {
    const letter = i < buf.length && isLetter(buf[i])
    if (letter && start < 0) start = i
    if (!letter && start >= 0) {
      const w = buf.toString('latin1', start, i).toLowerCase()
      counts.set(w, (counts.get(w) ?? 0) + 1)
      start = -1
    }
  }
  return [...counts]
    .sort((a, b) => b[1] - a[1] || byWord(a[0], b[0]))
    .slice(0, 10)
    .map(([w, n]) => `${n} ${w}`)
    .join('\n')
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = solve(readFileSync(0))
  process.stdout.write(out ? out + '\n' : '')
}
