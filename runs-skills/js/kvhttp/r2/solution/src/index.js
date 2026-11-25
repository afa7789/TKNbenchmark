import { createKvServer } from './server.js';

const arg = process.argv[2];
const port = Number(arg);
if (!Number.isInteger(port) || port < 0 || port > 65535) {
  console.error(`usage: app <port>  (got ${JSON.stringify(arg)})`);
  process.exit(2);
}

const server = createKvServer();
server.on('error', (err) => {
  console.error(`server error: ${err.message}`);
  process.exitCode = 1;
});
server.listen({ port, host: '127.0.0.1', backlog: 1024 });

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => {
    server.close();
    server.closeAllConnections();
  });
}
