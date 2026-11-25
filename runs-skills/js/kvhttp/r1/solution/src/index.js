import { createApp } from './lib/app.js';

const port = Number(process.argv[2]);
if (!Number.isInteger(port) || port < 0 || port > 65535) {
  console.error('usage: app <port>');
  process.exit(2);
}

const server = createApp();
server.maxConnections = 4096;
server.listen({ port, host: '127.0.0.1', backlog: 1024 }, () => {
  console.error(`kvhttp listening on 127.0.0.1:${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
