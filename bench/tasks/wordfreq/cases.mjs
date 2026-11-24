import { genInput, sha256 } from '../../harness/check.mjs'
import { solve } from './reference.mjs'

const lit = (name, stdin) => ({ name, stdin, stdout: solve(Buffer.from(stdin)) })
const b64 = (name, bytes) => ({ name, stdinB64: Buffer.from(bytes).toString('base64'), stdout: solve(Buffer.from(bytes)) })

function generated(name, gen, timeoutMs, inline) {
  const out = solve(genInput(gen))
  return inline ? { name, gen, timeoutMs, stdout: out } : { name, gen, timeoutMs, stdoutSha256: sha256(Buffer.from(out, 'latin1')) }
}

const twelve = 'zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha'

export const visible = () => ({
  kind: 'stdio',
  cases: [
    lit('simple', 'The cat and the hat.'),
    lit('case-folding', 'Hello, hello! HELLO? world.\n'),
    lit('top-10-and-ties', twelve),
    lit('empty', ''),
    lit('separators', "don't stop_me 4now, now-NOW"),
    generated('medium-200kb', { type: 'words', seed: 1, bytes: 200_000 }, 5000, true),
  ],
})

export const hidden = () => ({
  kind: 'stdio',
  cases: [
    ...visible().cases,
    b64('utf8-letters-are-separators', Buffer.from('café crème Café naïve', 'utf8')),
    b64('invalid-utf8', [0xff, 0x61, 0x62, 0xfe, 0x61, 0x62, 0x0a, 0xc3, 0x28, 0x41, 0x42]),
    lit('no-words', '!!! 123 ... ___ \n\t 42'),
    lit('single-word-no-newline', 'Word'),
    lit('all-ties', 'p o n m l k j i h g f e d c b a'),
    lit('long-word', 'x'.repeat(100_000) + ' y ' + 'x'.repeat(100_000)),
    lit('crlf', 'one two\r\ntwo three\r\nthree three\r\n'),
    generated('large-30mb', { type: 'words', seed: 7, bytes: 30_000_000 }, 10000, false),
  ],
})
