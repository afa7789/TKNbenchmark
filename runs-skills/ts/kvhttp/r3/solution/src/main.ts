import { createKvServer } from './server.ts';

const portArg = process.argv[2];
const port = Number(portArg);
if (portArg === undefined || !Number.isInteger(port) || port < 1 || port > 65535) {
  console.error('usage: app <port>');
  process.exit(2);
}

const server = createKvServer();
server.maxConnections = 1024;
server.on('error', (err) => {
  console.error(`server error: ${err.message}`);
  process.exit(1);
});
server.listen({ host: '127.0.0.1', port, backlog: 511 });

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
