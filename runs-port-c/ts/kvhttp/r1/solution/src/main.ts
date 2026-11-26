import { createKvServer } from './server.ts';

function parsePort(arg: string): number | undefined {
  if (!/^\d+$/.test(arg)) return undefined;
  const port = Number(arg);
  return port >= 1 && port <= 65535 ? port : undefined;
}

function main(argv: string[]): void {
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
    console.error(`listen: ${err.message}`);
    process.exit(1);
  });
  server.listen({ port, host: '127.0.0.1', backlog: 511 });
}

main(process.argv.slice(2));
