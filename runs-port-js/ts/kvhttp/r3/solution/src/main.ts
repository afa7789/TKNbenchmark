#!/usr/bin/env node
import { createApp } from './server.ts'

const port = Number(process.argv[2])
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  console.error('usage: app <port>')
  process.exit(2)
}

const server = createApp()
server.on('error', (err: Error) => {
  console.error(`kvhttp: ${err.message}`)
  process.exit(1)
})
server.listen({ port, host: '127.0.0.1', backlog: 1024 })

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => server.close(() => process.exit(0)))
}
