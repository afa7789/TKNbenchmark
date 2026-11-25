import { createKvServer } from './server.js';

const port = Number(process.argv[2]);
if (!Number.isInteger(port) || port < 0 || port > 65535) {
  console.error('usage: app <port>');
  process.exitCode = 2;
} else {
  const server = createKvServer();
  server.listen({ port, host: '127.0.0.1', backlog: 1024 });
  server.on('error', (err) => {
    console.error(`server error: ${err.message}`);
    process.exitCode = 1;
  });
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => server.close(() => process.exit(0)));
  }
}
