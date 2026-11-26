/**
 * HTTP/1.1 front end for the key-value App.
 *
 * Handles one request per connection and always closes the connection after
 * responding, which is all the protocol contract requires.
 */
import http from 'node:http';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { once } from 'node:events';
import type { Duplex } from 'node:stream';
import { App, MAX_VALUE_BYTES } from './app.ts';
import type { Response } from './app.ts';

const READ_TIMEOUT_MS = 30_000;
const LISTEN_BACKLOG = 1024;

class PayloadTooLargeError extends Error {}

interface ParserError extends Error {
  code?: string;
  rawPacket?: Buffer;
}

function parseRequestLine(raw: Buffer | undefined): { method: string; path: string } | undefined {
  if (!raw) return undefined;
  const end = raw.indexOf('\r\n');
  if (end < 0) return undefined;
  const parts = raw.toString('latin1', 0, end).split(' ');
  if (parts.length !== 3 || !parts[2]!.startsWith('HTTP/')) return undefined;
  const [method, target] = parts as [string, string, string];
  if (!/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(method)) return undefined;
  return { method, path: target.split('?', 1)[0]! };
}

/** Serializes a response for writing directly to a socket. */
function encodeRaw({ status, body = Buffer.alloc(0), headers = {} }: Response): Buffer {
  const lines = [`HTTP/1.1 ${status} ${http.STATUS_CODES[status] ?? ''}`];
  for (const [name, value] of Object.entries({ ...headers, 'Content-Length': String(body.length), Connection: 'close' })) {
    lines.push(`${name}: ${value}`);
  }
  return Buffer.concat([Buffer.from(lines.join('\r\n') + '\r\n\r\n', 'latin1'), body]);
}

async function readBody(req: IncomingMessage): Promise<Buffer> {
  const declared = req.headers['content-length'];
  if (declared !== undefined && Number(declared) > MAX_VALUE_BYTES) {
    throw new PayloadTooLargeError();
  }
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    total += chunk.length;
    if (total > MAX_VALUE_BYTES) throw new PayloadTooLargeError();
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, total);
}

function send(res: ServerResponse, { status, body = Buffer.alloc(0), headers = {} }: Response): void {
  res.writeHead(status, {
    ...headers,
    'Content-Length': String(body.length),
    Connection: 'close',
  });
  res.end(body);
}

export function createServer(app: App = new App()): http.Server {
  const server = http.createServer(
    { requestTimeout: READ_TIMEOUT_MS, headersTimeout: READ_TIMEOUT_MS, keepAlive: false },
    (req, res) => {
      void serve(app, req, res);
    },
  );
  server.on('clientError', (err: ParserError, socket: Duplex) => {
    if (!socket.writable) {
      socket.destroy();
      return;
    }
    // llhttp only knows a fixed set of methods. Route requests with any other
    // method so they get the same 404/400/405 answers as known methods would.
    const line = err.code === 'HPE_INVALID_METHOD' ? parseRequestLine(err.rawPacket) : undefined;
    const response: Response = line ? app.handle({ ...line, body: Buffer.alloc(0) }) : { status: 400 };
    socket.end(encodeRaw(response));
  });
  return server;
}

async function serve(app: App, req: IncomingMessage, res: ServerResponse): Promise<void> {
  let response: Response;
  try {
    const body = await readBody(req);
    const path = (req.url ?? '/').split('?', 1)[0]!;
    response = app.handle({ method: req.method ?? 'GET', path, body });
  } catch (err) {
    if (err instanceof PayloadTooLargeError) {
      send(res, { status: 413 });
      req.socket.destroySoon();
      return;
    }
    // Client went away or the body stream failed; nothing useful to send.
    if (!req.socket.destroyed) {
      console.error('error while reading request:', err);
      req.socket.destroy();
    }
    return;
  }
  try {
    send(res, response);
  } catch (err) {
    console.error('unhandled error while serving request:', err);
    res.destroy();
  }
}

export async function listen(port: number, host = '127.0.0.1'): Promise<http.Server> {
  const server = createServer();
  server.listen({ port, host, backlog: LISTEN_BACKLOG });
  await once(server, 'listening');
  return server;
}
