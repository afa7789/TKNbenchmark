import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

// A JS Map iterates in insertion order, so delete + set moves a key to the "most recent" end.
const COMMANDS = {
  SET(m, cap, k, v) {
    m.delete(k)
    m.set(k, v)
    if (m.size > cap) m.delete(m.keys().next().value)
  },
  GET(m, cap, k) {
    if (!m.has(k)) return 'NULL'
    const v = m.get(k)
    m.delete(k)
    m.set(k, v)
    return v
  },
  DEL: (m, cap, k) => (m.delete(k) ? '1' : '0'),
  SIZE: (m) => String(m.size),
}

export function solve(buf) {
  const lines = buf.toString('latin1').split('\n')
  const cap = Number(lines[0])
  const m = new Map()
  const out = []
  for (const line of lines.slice(1)) {
    if (!line) continue
    const [cmd, k, v] = line.split(' ')
    const r = COMMANDS[cmd](m, cap, k, v)
    if (r !== undefined) out.push(r)
  }
  return out.join('\n')
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = solve(readFileSync(0))
  process.stdout.write(out ? out + '\n' : '')
}
