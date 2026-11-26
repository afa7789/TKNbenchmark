import { createKvServer } from './server.ts';

function parsePort(arg: string): number | undefined {
  if (!/^\d+$/.test(arg)) return undefined;
  const port = Number(arg);
  return port <= 65535 ? port : undefined;
}

function main(argv: readonly string[]): void {
  if (argv.length !== 1) {
    console.error('usage: app <port>');
    process.exit(2);
  }
  const port = parsePort(argv[0]!);
  if (port === undefined) {
    console.error(`invalid port: ${argv[0]}`);
    process.exit(2);
  }

  const server = createKvServer();
  server.on('error', (err) => {
    console.error(`server error: ${err.message}`);
    process.exit(1);
  });
  server.listen({ host: '127.0.0.1', port, backlog: 1024 });

  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.once(signal, () => {
      server.close();
      server.closeAllConnections();
    });
  }
}

main(process.argv.slice(2));
