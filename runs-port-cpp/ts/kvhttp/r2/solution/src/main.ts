import { KvStore } from './kvStore.ts';
import { route } from './routes.ts';
import { startServer } from './server.ts';

function parsePort(arg: string | undefined): number | undefined {
  if (arg === undefined || !/^\d{1,5}$/.test(arg)) return undefined;
  const port = Number(arg);
  return port >= 1 && port <= 65535 ? port : undefined;
}

const args = process.argv.slice(2);
if (args.length !== 1) {
  console.error('usage: app <port>');
  process.exit(2);
}
const port = parsePort(args[0]);
if (port === undefined) {
  console.error(`invalid port: ${args[0]}`);
  process.exit(2);
}

const store = new KvStore();
try {
  await startServer({ port }, (request) => route(store, request));
} catch (error) {
  console.error('fatal:', error instanceof Error ? error.message : error);
  process.exit(1);
}
