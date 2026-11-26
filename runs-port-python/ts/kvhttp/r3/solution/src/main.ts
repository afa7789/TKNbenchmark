import { listen } from './server.ts';

function parsePort(args: readonly string[]): number | undefined {
  if (args.length !== 1 || !/^\d+$/.test(args[0]!)) return undefined;
  const port = Number(args[0]);
  return port > 0 && port < 65536 ? port : undefined;
}

async function main(argv: readonly string[]): Promise<number> {
  const port = parsePort(argv);
  if (port === undefined) {
    console.error('usage: app <port>');
    return 2;
  }
  const server = await listen(port);
  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.once(signal, () => {
      server.close();
      server.closeAllConnections();
    });
  }
  return 0;
}

process.exitCode = await main(process.argv.slice(2));
