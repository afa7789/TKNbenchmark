import { STATUS_CODES, createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

import { MAX_VALUE_LENGTH, route, type Response } from './routes.ts';
import type { KvStore } from './store.ts';

const MAX_HEADER_BYTES = 64 * 1024;
const REQUEST_TIMEOUT_MS = 30_000;

class PayloadTooLargeError extends Error {}

const REQUEST_LINE = /^[\r\n]*([!#$%&'*+.^_`|~0-9A-Za-z-]+) (\S+) HTTP\/1\.\d\r?\n/;

/**
 * Picks the status for a request Node's parser rejected. Methods outside Node's
 * built-in list are still well-formed HTTP, so they get routed (always yielding
 * 400/404/405) instead of a blanket 400.
 */
function clientErrorStatus(store: KvStore, err: NodeJS.ErrnoException & { rawPacket?: Buffer }): number {
  if (err.code === 'HPE_HEADER_OVERFLOW') return 431;
  if (err.code === 'HPE_INVALID_METHOD' && err.rawPacket !== undefined) {
    const match = REQUEST_LINE.exec(err.rawPacket.toString('latin1'));
    if (match?.[1] !== undefined && match[2] !== undefined) {
      return route(store, { method: match[1], path: match[2], body: Buffer.alloc(0) }).status;
    }
  }
  return 400;
}

function send(res: ServerResponse, { status, contentType, body }: Response): void {
  if (status === 204) {
    res.writeHead(status).end();
    return;
  }
  const payload = typeof body === 'string' ? Buffer.from(body) : (body ?? Buffer.alloc(0));
  const headers: Record<string, string | number> = { 'Content-Length': payload.length };
  if (contentType !== undefined) headers['Content-Type'] = contentType;
  res.writeHead(status, headers).end(payload);
}

/** Reads the whole request body, rejecting bodies larger than `limit` bytes. */
async function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > limit) throw new PayloadTooLargeError();
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

function declaredLength(req: IncomingMessage): number | undefined {
  const header = req.headers['content-length'];
  return header === undefined ? undefined : Number(header);
}

async function handle(store: KvStore, req: IncomingMessage, res: ServerResponse): Promise<void> {
  res.shouldKeepAlive = false;

  const declared = declaredLength(req);
  if (declared !== undefined && declared > MAX_VALUE_LENGTH) {
    req.resume(); // drain so the client sees the response rather than a reset
    send(res, { status: 413 });
    return;
  }

  let body: Buffer;
  try {
    body = await readBody(req, MAX_VALUE_LENGTH);
  } catch (err) {
    if (err instanceof PayloadTooLargeError) {
      req.resume();
      send(res, { status: 413 });
    } else {
      res.destroy();
    }
    return;
  }

  // Request paths never carry a query string, but strip one defensively.
  const target = req.url ?? '';
  const queryAt = target.indexOf('?');
  const path = queryAt === -1 ? target : target.slice(0, queryAt);

  send(res, route(store, { method: req.method ?? '', path, body }));
}

export function createKvServer(store: KvStore): Server {
  const server = createServer(
    {
      keepAlive: false,
      maxHeaderSize: MAX_HEADER_BYTES,
      requestTimeout: REQUEST_TIMEOUT_MS,
    },
    (req, res) => {
      handle(store, req, res).catch((err: unknown) => {
        console.error('request failed:', err);
        if (!res.headersSent) send(res, { status: 500 });
        else res.destroy();
      });
    },
  );
  server.on('clientError', (err: NodeJS.ErrnoException & { rawPacket?: Buffer }, socket) => {
    if (!socket.writable) {
      socket.destroy();
      return;
    }
    const status = clientErrorStatus(store, err);
    socket.end(`HTTP/1.1 ${status} ${STATUS_CODES[status]}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n`);
  });
  return server;
}

/** Starts serving on 127.0.0.1:`port` and resolves once listening. */
export function listen(server: Server, port: number): Promise<AddressInfo> {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen({ host: '127.0.0.1', port, backlog: 1024 }, () => {
      server.off('error', reject);
      resolve(server.address() as AddressInfo);
    });
  });
}
