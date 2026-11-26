/** kvhttp: an in-memory HTTP/1.1 key-value server. Usage: app <port> */
import { createKvServer, listen } from './server.ts';
import { KvStore } from './store.ts';

function parsePort(arg: string | undefined): number | undefined {
  if (arg === undefined || !/^\d+$/.test(arg)) return undefined;
  const port = Number(arg);
  return port >= 1 && port <= 65535 ? port : undefined;
}

const args = process.argv.slice(2);
const port = args.length === 1 ? parsePort(args[0]) : undefined;
if (port === undefined) {
  console.error('usage: app <port>');
  process.exit(2);
}

try {
  await listen(createKvServer(new KvStore()), port);
} catch (err) {
  console.error(`listen: ${(err as Error).message}`);
  process.exit(1);
}
