import { Router } from './router.ts';
import { startServer } from './server.ts';
import { Store } from './store.ts';

function parsePort(arg: string): number {
  const value = /^[0-9]+$/.test(arg) ? Number(arg) : NaN;
  if (!Number.isInteger(value) || value < 1 || value > 65535) {
    console.error(`kvhttp: invalid port '${arg}'`);
    process.exit(2);
  }
  return value;
}

async function main(argv: string[]): Promise<void> {
  if (argv.length !== 1) {
    console.error('usage: app <port>');
    process.exit(2);
  }
  const port = parsePort(argv[0]!);
  const router = new Router(new Store());
  try {
    await startServer(port, router);
  } catch (error) {
    console.error(`kvhttp: listen: ${(error as Error).message}`);
    process.exit(1);
  }
}

await main(process.argv.slice(2));
