import { createServer } from 'node:http';
import { createRequestListener } from './handler.ts';
import { KvStore } from './store.ts';

const HOST = '127.0.0.1';
const BACKLOG = 1024;

function parsePort(args: readonly string[]): number {
  if (args.length !== 1) {
    console.error('usage: app <port>');
    process.exit(2);
  }
  const arg = args[0]!;
  const port = Number(arg);
  if (!/^\d+$/.test(arg) || port > 65535) {
    console.error(`invalid port: ${arg}`);
    process.exit(2);
  }
  return port;
}

const port = parsePort(process.argv.slice(2));
const server = createServer({ keepAlive: false }, createRequestListener(new KvStore()));

server.on('clientError', (_error, socket) => {
  if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
  else socket.destroy();
});

server.on('error', (error) => {
  console.error('server error:', error);
  process.exit(1);
});

server.listen({ host: HOST, port, backlog: BACKLOG });

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
