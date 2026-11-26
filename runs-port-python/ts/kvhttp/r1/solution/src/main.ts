/** kvhttp: a small in-memory HTTP/1.1 key-value server. */

import { parseArgs } from 'node:util'
import { App } from './app.ts'
import { Server } from './server.ts'

const USAGE = 'usage: kvhttp [--host HOST] port'

function fail(message: string): never {
  console.error(`${USAGE}\nkvhttp: error: ${message}`)
  process.exit(2)
}

function parseCli(argv: string[]): { host: string; port: number } {
  let parsed
  try {
    parsed = parseArgs({
      args: argv,
      options: {
        host: { type: 'string', default: '127.0.0.1' },
        help: { type: 'boolean', short: 'h' },
      },
      allowPositionals: true,
    })
  } catch (err) {
    fail(err instanceof Error ? err.message : String(err))
  }
  if (parsed.values.help) {
    console.log(USAGE)
    process.exit(0)
  }
  const [rawPort, ...extra] = parsed.positionals
  if (rawPort === undefined) fail('the following arguments are required: port')
  if (extra.length > 0) fail(`unrecognized arguments: ${extra.join(' ')}`)
  const port = Number(rawPort)
  if (!/^\s*[+-]?\d+\s*$/.test(rawPort) || !Number.isInteger(port) || port < 0 || port > 65535) {
    fail(`argument port: invalid port value: '${rawPort}'`)
  }
  return { host: parsed.values.host, port }
}

async function main(): Promise<void> {
  const { host, port } = parseCli(process.argv.slice(2))
  await new Server(new App()).listen(host, port)
  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.once(signal, () => process.exit(0))
  }
}

main().catch((err: unknown) => {
  console.error('kvhttp:', err instanceof Error ? err.message : err)
  process.exit(1)
})
