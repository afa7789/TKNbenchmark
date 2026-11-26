import net from 'node:net';
import type { Socket } from 'node:net';

import { HttpError, SocketReader, readRequest, serializeResponse } from './http.ts';
import type { Response } from './http.ts';
import type { Router } from './router.ts';

const IO_TIMEOUT_MS = 30_000;
const DRAIN_TIMEOUT_MS = 2_000;
const MAX_DRAIN_BYTES = 64 * 1024 * 1024;

/**
 * After the response is written, half-close and discard any unread request
 * bytes (e.g. an oversized body we rejected) so closing does not trigger a RST
 * that could clobber the reply.
 */
function finishAndDrain(socket: Socket, payload: Buffer): void {
  let drained = 0;
  socket.setTimeout(DRAIN_TIMEOUT_MS, () => socket.destroy());
  socket.on('data', (chunk: Buffer) => {
    drained += chunk.length;
    if (drained >= MAX_DRAIN_BYTES) socket.destroy();
  });
  socket.on('end', () => {
    if (socket.writableFinished) socket.destroy();
    else socket.once('finish', () => socket.destroy());
  });
  socket.end(payload);
  socket.resume();
}

async function serveConnection(socket: Socket, router: Router): Promise<void> {
  socket.setNoDelay(true);
  socket.setTimeout(IO_TIMEOUT_MS);
  // Write failures surface here; the connection is simply dropped.
  socket.on('error', () => socket.destroy());

  const reader = new SocketReader(socket);
  let response: Response;
  try {
    const request = await readRequest(reader);
    if (request === undefined) {
      socket.destroy();
      return;
    }
    response = router.handle(request);
  } catch (error) {
    if (error instanceof HttpError) {
      response = { status: error.status };
    } else {
      console.error('kvhttp: request failed:', error);
      response = { status: 500 };
    }
  } finally {
    reader.release();
  }
  if (socket.destroyed) return;
  finishAndDrain(socket, serializeResponse(response));
}

/** Starts listening on 127.0.0.1:<port>; resolves once the socket is bound. */
export function startServer(port: number, router: Router): Promise<net.Server> {
  const server = net.createServer({ allowHalfOpen: true }, (socket) => {
    void serveConnection(socket, router);
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen({ port, host: '127.0.0.1', backlog: 511 }, () => {
      server.off('error', reject);
      resolve(server);
    });
  });
}
