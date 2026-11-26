import http, { type IncomingMessage, type ServerResponse } from 'node:http';
import { textResponse, type Handler, type Response } from './http.ts';

export interface ServerOptions {
  readonly port: number;
  readonly host?: string;
  readonly maxHeadBytes?: number;
  readonly maxBodyBytes?: number;
  readonly ioTimeoutMs?: number;
}

class HttpError extends Error {
  readonly status: number;

  constructor(status: number) {
    super(http.STATUS_CODES[status] ?? 'Error');
    this.status = status;
  }
}

/** Collects the request body, rejecting with 413 once it exceeds `limit` bytes. */
function readBody(req: IncomingMessage, limit: number): Promise<Buffer> {
  const declared = req.headers['content-length'];
  if (declared !== undefined && Number(declared) > limit) {
    return Promise.reject(new HttpError(413));
  }
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    const onData = (chunk: Buffer): void => {
      size += chunk.length;
      if (size > limit) {
        req.off('data', onData);
        reject(new HttpError(413));
        return;
      }
      chunks.push(chunk);
    };
    req.on('data', onData);
    req.once('end', () => resolve(Buffer.concat(chunks, size)));
    req.once('error', reject);
  });
}

function send(req: IncomingMessage, res: ServerResponse, response: Response): void {
  const body = response.body ?? '';
  res.statusCode = response.status;
  for (const [name, value] of Object.entries(response.headers ?? {})) {
    res.setHeader(name, value);
  }
  if (response.status !== 204) {
    res.setHeader('Content-Length', Buffer.byteLength(body));
  }
  res.setHeader('Connection', 'close');
  // Keep draining any unread request bytes so the client sees the response
  // rather than a connection reset.
  req.resume();
  res.end(response.status === 204 ? undefined : body);
}

/** Starts an HTTP/1.1 server that serves every request through `handler`. */
export function startServer(options: ServerOptions, handler: Handler): Promise<http.Server> {
  const maxBodyBytes = options.maxBodyBytes ?? 1024 * 1024;
  const ioTimeoutMs = options.ioTimeoutMs ?? 10_000;

  const server = http.createServer(
    { maxHeaderSize: options.maxHeadBytes ?? 64 * 1024, keepAlive: false },
    (req, res) => {
      readBody(req, maxBodyBytes).then(
        (body) => {
          let response: Response;
          try {
            response = handler({ method: req.method ?? '', path: req.url ?? '', body });
          } catch (error) {
            console.error('handler error:', error);
            response = textResponse(500, 'Internal Server Error');
          }
          send(req, res, response);
        },
        (error: unknown) => {
          const status = error instanceof HttpError ? error.status : 400;
          send(req, res, textResponse(status, http.STATUS_CODES[status] ?? 'Error'));
        },
      );
    },
  );
  server.headersTimeout = ioTimeoutMs;
  server.requestTimeout = ioTimeoutMs * 3;
  server.keepAliveTimeout = 0;

  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(options.port, options.host ?? '127.0.0.1', () => {
      server.off('error', reject);
      resolve(server);
    });
  });
}
