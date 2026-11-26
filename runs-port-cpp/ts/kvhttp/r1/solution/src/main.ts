import { createServer, type Socket } from 'node:net';
import { DEFAULT_LIMITS, RequestParser, emptyResponse, writeResponse, type Response } from './http.ts';
import { KvStore } from './kvStore.ts';
import { Router } from './router.ts';

const IDLE_TIMEOUT_MS = 30_000;

function parsePort(raw: string): number | undefined {
  if (!/^[0-9]+$/.test(raw)) return undefined;
  const port = Number(raw);
  return port >= 1 && port <= 65535 ? port : undefined;
}

function serveConnection(socket: Socket, router: Router): void {
  socket.setNoDelay(true);
  // Don't let an idle or stalled client hold a connection forever.
  socket.setTimeout(IDLE_TIMEOUT_MS, () => socket.destroy());
  socket.on('error', () => socket.destroy());

  const parser = new RequestParser(DEFAULT_LIMITS);
  const onData = (chunk: Buffer): void => {
    const event = parser.push(chunk);
    if (event === undefined) return;
    socket.off('data', onData);
    // Keep draining anything the client still sends so the close is clean.
    socket.resume();

    let response: Response;
    if (event.kind === 'error') {
      response = event.response;
    } else {
      try {
        response = router.handle(event.request);
      } catch {
        response = emptyResponse(500);
      }
    }
    writeResponse(socket, response);
  };
  socket.on('data', onData);
  // Peer closed before sending a full request: nothing to answer.
  socket.on('end', () => socket.end());
}

function main(argv: readonly string[]): number | undefined {
  if (argv.length !== 1) {
    console.error('usage: app <port>');
    return 2;
  }
  const port = parsePort(argv[0] ?? '');
  if (port === undefined) {
    console.error(`invalid port: ${argv[0]}`);
    return 2;
  }

  const router = new Router(new KvStore());
  const server = createServer({ allowHalfOpen: true }, (socket) => serveConnection(socket, router));
  server.on('error', (err) => {
    console.error(`fatal: ${err.message}`);
    process.exit(1);
  });
  server.listen({ host: '127.0.0.1', port, backlog: 511 });
  return undefined;
}

const code = main(process.argv.slice(2));
if (code !== undefined) process.exitCode = code;
