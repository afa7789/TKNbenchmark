// Reference for suite: dispatches the first argument to the wordfreq, lru or calc reference.
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { solve as wordfreq } from '../wordfreq/reference.mjs'
import { solve as lru } from '../lru/reference.mjs'
import { solve as calc } from '../calc/reference.mjs'

export const SUBCOMMANDS = { wordfreq, lru, calc }

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const solve = SUBCOMMANDS[process.argv[2]]
  if (!solve) process.exit(2)
  const out = solve(readFileSync(0))
  process.stdout.write(out ? out + '\n' : '')
}
