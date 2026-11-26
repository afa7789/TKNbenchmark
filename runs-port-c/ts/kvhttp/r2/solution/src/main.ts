/** kvhttp: an HTTP/1.1 in-memory key-value server. Usage: app <port> */
import { createServer } from './server.ts';
import { Store } from './store.ts';

function parsePort(arg: string | undefined): number | undefined {
  if (arg === undefined || !/^\d+$/.test(arg)) return undefined;
  const port = Number(arg);
  return port >= 1 && port <= 65535 ? port : undefined;
}

function main(argv: string[]): void {
  const port = parsePort(argv.length === 1 ? argv[0] : undefined);
  if (port === undefined) {
    console.error('usage: app <port>');
    process.exit(2);
  }

  const server = createServer(new Store());
  server.on('error', (err) => {
    console.error(`kvhttp: ${err.message}`);
    process.exit(1);
  });
  server.listen({ port, host: '127.0.0.1', backlog: 511 });
}

main(process.argv.slice(2));
