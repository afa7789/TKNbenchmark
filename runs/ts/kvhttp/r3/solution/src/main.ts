import { createServer } from './server.ts';

function parsePort(arg: string | undefined): number {
  const port = Number(arg);
  if (!arg || !Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('usage: app <port>');
    process.exit(2);
  }
  return port;
}

const port = parsePort(process.argv[2]);
const server = createServer();

server.on('error', (err) => {
  console.error(`server error: ${err.message}`);
  process.exit(1);
});

server.listen({ host: '127.0.0.1', port, backlog: 511 }, () => {
  console.log(`kvhttp listening on http://127.0.0.1:${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    server.close();
    server.closeAllConnections();
    process.exit(0);
  });
}
