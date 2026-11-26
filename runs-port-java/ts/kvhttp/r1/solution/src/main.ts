import { createServer } from 'node:http';
import { createHandler } from './handler.ts';
import { KvStore } from './store.ts';

const BACKLOG = 1024;

function parsePort(arg: string | undefined): number {
  const port = Number(arg);
  if (arg === undefined || !/^\d+$/.test(arg) || port > 65535) {
    console.error(arg === undefined ? 'usage: app <port>' : `invalid port: ${arg}`);
    process.exit(2);
  }
  return port;
}

function main(argv: readonly string[]): void {
  if (argv.length !== 1) {
    console.error('usage: app <port>');
    process.exit(2);
  }
  const port = parsePort(argv[0]);

  const server = createServer(createHandler(new KvStore()));
  server.on('error', (err) => {
    console.error(`server error: ${err.message}`);
    process.exit(1);
  });
  server.listen({ host: '127.0.0.1', port, backlog: BACKLOG });

  const shutdown = (): void => {
    server.close();
    server.closeAllConnections();
  };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
}

main(process.argv.slice(2));
