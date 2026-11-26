/** Entry point: `app <port>` serves the key-value API on 127.0.0.1. */
import http from 'node:http';
import { makeHandler, type Response } from './handler.ts';
import { Store } from './store.ts';

/** Largest accepted request body: 1 MiB values plus generous headroom. */
const MAX_BODY = 8 * 1024 * 1024;

class BodyTooLarge extends Error {}

function parsePort(arg: string | undefined): number | undefined {
  if (arg === undefined || !/^\d+$/.test(arg)) return undefined;
  const n = Number(arg);
  return n >= 1 && n <= 65535 ? n : undefined;
}

async function readBody(req: http.IncomingMessage): Promise<Buffer> {
  const declared = Number(req.headers['content-length'] ?? 0);
  if (declared > MAX_BODY) throw new BodyTooLarge();
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > MAX_BODY) throw new BodyTooLarge();
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

function send(res: http.ServerResponse, { status, headers, body }: Response): void {
  res.writeHead(status, { ...headers, 'Content-Length': body.length });
  res.end(body);
}

function main(): void {
  const port = parsePort(process.argv[2]);
  if (port === undefined) {
    console.error('usage: app <port>');
    process.exit(2);
  }

  const handle = makeHandler(new Store());
  const server = http.createServer(async (req, res) => {
    try {
      const body = await readBody(req);
      const path = (req.url ?? '/').split('?', 1)[0]!;
      send(res, handle({ method: req.method ?? 'GET', path, body }));
    } catch (err) {
      const status = err instanceof BodyTooLarge ? 413 : 500;
      if (!res.headersSent) send(res, { status, headers: { Connection: 'close' }, body: Buffer.alloc(0) });
      else res.destroy();
    }
  });

  server.listen({ host: '127.0.0.1', port, backlog: 1024 }, () => {
    console.log(`kvhttp listening on 127.0.0.1:${port}`);
  });
}

main();
