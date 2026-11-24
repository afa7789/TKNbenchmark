import { createApp } from './server.ts';

function parsePort(raw: string | undefined): number {
  const port = Number(raw);
  if (!raw || !Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('usage: app <port>');
    process.exit(2);
  }
  return port;
}

const port = parsePort(process.argv[2]);
const server = createApp();

server.on('error', (err) => {
  console.error(`server error: ${err.message}`);
  process.exit(1);
});

server.listen({ port, host: '127.0.0.1', backlog: 511 }, () => {
  console.error(`kvhttp listening on 127.0.0.1:${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
