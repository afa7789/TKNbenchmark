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
server.maxConnections = 4096;
server.listen({ port, host: '127.0.0.1', backlog: 1024 }, () => {
  console.error(`kvhttp listening on 127.0.0.1:${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    server.close();
    server.closeAllConnections();
    process.exit(0);
  });
}
