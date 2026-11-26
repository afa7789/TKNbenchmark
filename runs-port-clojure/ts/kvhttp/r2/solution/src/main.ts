import { createServer } from 'node:http';
import { createHandler } from './handler.ts';
import { Store } from './store.ts';

const HOST = '127.0.0.1';

function parsePort(arg: string | undefined): number | undefined {
  if (arg === undefined || !/^\d+$/.test(arg)) return undefined;
  const port = Number(arg);
  return port > 0 && port < 65536 ? port : undefined;
}

function main(argv: readonly string[]): void {
  const port = parsePort(argv[0]);
  if (port === undefined) {
    console.error('usage: app <port>');
    process.exit(2);
  }

  const server = createServer({ keepAlive: false }, createHandler(new Store()));
  server.on('clientError', (_err, socket) => {
    if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
    else socket.destroy();
  });
  server.on('error', (err) => {
    console.error(`failed to listen on ${HOST}:${port}:`, err.message);
    process.exit(1);
  });
  server.listen({ host: HOST, port, backlog: 1024 });

  const shutdown = (): void => {
    server.close(() => process.exit(0));
    server.closeAllConnections();
  };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
}

main(process.argv.slice(2));
