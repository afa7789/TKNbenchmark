import { createKvServer } from './server.ts';

function parsePort(arg: string | undefined): number {
  const port = Number(arg);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('usage: app <port>');
    process.exit(2);
  }
  return port;
}

const port = parsePort(process.argv[2]);
const server = createKvServer();
server.on('error', (err) => {
  console.error(`server error: ${err.message}`);
  process.exit(1);
});
server.listen({ port, host: '127.0.0.1', backlog: 1024 });

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    server.close();
    server.closeAllConnections();
    process.exit(0);
  });
}
