import net from "node:net";
import type { App } from "./app.ts";
import { HttpError, type Response, serializeResponse } from "./http.ts";
import { readRequest } from "./parser.ts";
import { StreamReader } from "./reader.ts";

/** Serves one request per connection, then closes it. */
export class Server {
  readonly #app: App;

  constructor(app: App) {
    this.#app = app;
  }

  listen(host: string, port: number): Promise<net.Server> {
    const server = net.createServer({ allowHalfOpen: true }, (socket) => void this.#handleConnection(socket));
    return new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen({ host, port, backlog: 1024 }, () => {
        server.off("error", reject);
        resolve(server);
      });
    });
  }

  async #handleConnection(socket: net.Socket): Promise<void> {
    const reader = new StreamReader(socket);
    try {
      let response: Response;
      try {
        const request = await readRequest(reader);
        if (request === null) return;
        response = this.#app.handle(request);
      } catch (err) {
        if (!(err instanceof HttpError)) throw err;
        response = { status: err.status };
      }
      await write(socket, serializeResponse(response));
    } catch (err) {
      if (!isConnectionError(err)) console.error("unhandled error while serving request:", err);
    } finally {
      socket.destroy();
    }
  }
}

/** Writes and flushes the data, then half-closes the socket. */
function write(socket: net.Socket, data: Buffer): Promise<void> {
  return new Promise((resolve, reject) => {
    socket.end(data, () => resolve());
    socket.once("error", reject);
  });
}

function isConnectionError(err: unknown): boolean {
  return err instanceof Error && "code" in err && typeof err.code === "string";
}
