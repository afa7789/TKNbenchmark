/**
 * TCP server: reads one HTTP/1.1 request per connection, answers it with an
 * exact Content-Length and closes the connection.
 */

import net from 'node:net'
import { once } from 'node:events'
import type { App } from './app.ts'
import { HttpError, IncompleteReadError, readRequest, Response, Status, StreamReader } from './http.ts'

const READ_TIMEOUT_MS = 30_000
const LINGER_MS = 5_000

export class Server {
  readonly #app: App
  readonly #server: net.Server

  constructor(app: App) {
    this.#app = app
    this.#server = net.createServer({ noDelay: true }, (socket) => void this.#handleConnection(socket))
  }

  async listen(host: string, port: number): Promise<void> {
    this.#server.listen({ host, port, backlog: 1024 })
    await once(this.#server, 'listening')
  }

  close(): Promise<void> {
    return new Promise((resolve, reject) => this.#server.close((err) => (err ? reject(err) : resolve())))
  }

  async #handleConnection(socket: net.Socket): Promise<void> {
    const reader = new StreamReader(socket)
    socket.setTimeout(READ_TIMEOUT_MS, () => socket.destroy())

    let response: Response
    try {
      response = this.#app.handle(await readRequest(reader))
    } catch (err) {
      if (err instanceof HttpError) {
        response = new Response(err.status)
      } else if (err instanceof IncompleteReadError || isConnectionError(err)) {
        socket.destroy()
        return
      } else {
        console.error('unhandled error while processing request:', err)
        response = new Response(Status.INTERNAL_SERVER_ERROR)
      }
    }

    if (socket.destroyed) return
    // Keep draining whatever the client still sends so closing does not reset
    // the connection before it has read the response; give up after a while.
    socket.setTimeout(LINGER_MS, () => socket.destroy())
    socket.removeAllListeners('data')
    socket.on('data', () => {})
    socket.resume()
    socket.end(response.encode())
  }
}

function isConnectionError(err: unknown): boolean {
  return err instanceof Error && 'code' in err && typeof err.code === 'string'
}
