// suite = the wordfreq, lru and calc suites, each case run as `./app <subcommand>` and named
// <subcommand>/<case>. visible(sub) / hidden(sub) give one subcommand's cases (for a swarm worker).
import * as wordfreq from '../wordfreq/cases.mjs'
import * as lru from '../lru/cases.mjs'
import * as calc from '../calc/cases.mjs'

const SUBS = { wordfreq, lru, calc }

function suite(kind, only) {
  const subs = only ? [only] : Object.keys(SUBS)
  const cases = subs.flatMap((s) => SUBS[s][kind]().cases.map((c) => ({ ...c, name: `${s}/${c.name}`, args: [s, ...(c.args ?? [])] })))
  return { kind: 'stdio', cases }
}

export const visible = (_lang, only) => suite('visible', only)
export const hidden = (_lang, only) => suite('hidden', only)
