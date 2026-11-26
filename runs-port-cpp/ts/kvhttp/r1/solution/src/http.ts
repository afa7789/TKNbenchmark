import type { Socket } from 'node:net';

export interface Request {
  method: string;
  target: string;
  body: Buffer;
}

export interface Response {
  status: number;
  headers: ReadonlyArray<readonly [name: string, value: string]>;
  body?: Buffer;
}

export interface Limits {
  maxHeaderBytes: number;
  maxBodyBytes: number;
}

export const DEFAULT_LIMITS: Limits = {
  maxHeaderBytes: 64 * 1024,
  maxBodyBytes: 1024 * 1024,
};

const REASON_PHRASES: Readonly<Record<number, string>> = {
  200: 'OK',
  201: 'Created',
  204: 'No Content',
  400: 'Bad Request',
  404: 'Not Found',
  405: 'Method Not Allowed',
  408: 'Request Timeout',
  411: 'Length Required',
  413: 'Content Too Large',
  431: 'Request Header Fields Too Large',
  500: 'Internal Server Error',
  501: 'Not Implemented',
  505: 'HTTP Version Not Supported',
};

export function reasonPhrase(status: number): string {
  return REASON_PHRASES[status] ?? 'Unknown';
}

export function textResponse(status: number, body: string, contentType = 'text/plain; charset=utf-8'): Response {
  return { status, headers: [['Content-Type', contentType]], body: Buffer.from(body) };
}

export function emptyResponse(status: number, headers: Response['headers'] = []): Response {
  return { status, headers };
}

/** Thrown while parsing the request head; carries the status to answer with. */
class HttpError extends Error {
  readonly status: number;

  constructor(status: number) {
    super(`HTTP ${status}`);
    this.status = status;
  }
}

const HEADER_END = Buffer.from('\r\n\r\n');
const MAX_SIZE_T = 2n ** 64n - 1n;

interface RequestHead {
  method: string;
  target: string;
  contentLength: number;
}

function parseContentLength(raw: string): number {
  if (!/^[0-9]+$/.test(raw)) throw new HttpError(400);
  const value = BigInt(raw);
  if (value > MAX_SIZE_T) throw new HttpError(400);
  // Anything beyond the safe-integer range is far over any body limit anyway.
  return value > BigInt(Number.MAX_SAFE_INTEGER) ? Number.MAX_SAFE_INTEGER : Number(value);
}

function parseHead(head: string): RequestHead {
  const lineEnd = head.indexOf('\r\n');
  const requestLine = lineEnd === -1 ? head : head.slice(0, lineEnd);

  // request-line = method SP request-target SP HTTP-version
  const sp1 = requestLine.indexOf(' ');
  const sp2 = sp1 === -1 ? -1 : requestLine.indexOf(' ', sp1 + 1);
  if (sp2 === -1 || sp1 === 0 || sp2 === sp1 + 1) throw new HttpError(400);
  const version = requestLine.slice(sp2 + 1);
  if (!version.startsWith('HTTP/1.')) throw new HttpError(version.startsWith('HTTP/') ? 505 : 400);

  let contentLength: number | undefined;
  const headerLines = lineEnd === -1 ? [] : head.slice(lineEnd + 2).split('\r\n');
  for (const line of headerLines) {
    const colon = line.indexOf(':');
    if (colon <= 0) throw new HttpError(400);
    const name = line.slice(0, colon).toLowerCase();
    const value = line.slice(colon + 1).replace(/^[ \t]+|[ \t]+$/g, '');

    if (name === 'content-length') {
      const length = parseContentLength(value);
      if (contentLength !== undefined && contentLength !== length) throw new HttpError(400);
      contentLength = length;
    } else if (name === 'transfer-encoding') {
      throw new HttpError(501);
    }
  }

  return {
    method: requestLine.slice(0, sp1),
    target: requestLine.slice(sp1 + 1, sp2),
    contentLength: contentLength ?? 0,
  };
}

type ParserState =
  | { kind: 'head'; buffered: Buffer }
  | { kind: 'body'; head: RequestHead; body: Buffer; received: number }
  | { kind: 'discard'; remaining: number; status: number }
  | { kind: 'done' };

export type ParseEvent = { kind: 'request'; request: Request } | { kind: 'error'; response: Response };

/**
 * Incremental parser for a single HTTP/1.x request. Feed it socket chunks;
 * it yields a result once a full request (or a protocol error) is known.
 */
export class RequestParser {
  readonly #limits: Limits;
  #state: ParserState = { kind: 'head', buffered: Buffer.alloc(0) };

  constructor(limits: Limits = DEFAULT_LIMITS) {
    this.#limits = limits;
  }

  /** Consumes a chunk. Returns the outcome once the request is complete, otherwise undefined. */
  push(chunk: Buffer): ParseEvent | undefined {
    const state = this.#state;
    switch (state.kind) {
      case 'head':
        return this.#pushHead(state.buffered, chunk);
      case 'body':
        return this.#pushBody(state, chunk);
      case 'discard':
        return this.#pushDiscard(state, chunk);
      case 'done':
        return undefined;
    }
  }

  #finish(event: ParseEvent): ParseEvent {
    this.#state = { kind: 'done' };
    return event;
  }

  #fail(status: number): ParseEvent {
    return this.#finish({ kind: 'error', response: emptyResponse(status) });
  }

  #pushHead(previous: Buffer, chunk: Buffer): ParseEvent | undefined {
    const searchFrom = Math.max(previous.length - 3, 0);
    const buffered = previous.length === 0 ? chunk : Buffer.concat([previous, chunk]);
    const headerEnd = buffered.indexOf(HEADER_END, searchFrom);
    if (headerEnd === -1) {
      if (buffered.length > this.#limits.maxHeaderBytes) return this.#fail(431);
      this.#state = { kind: 'head', buffered };
      return undefined;
    }
    if (headerEnd > this.#limits.maxHeaderBytes) return this.#fail(431);

    let head: RequestHead;
    try {
      head = parseHead(buffered.toString('latin1', 0, headerEnd));
    } catch (err) {
      if (err instanceof HttpError) return this.#fail(err.status);
      throw err;
    }

    const rest = buffered.subarray(headerEnd + HEADER_END.length);
    if (head.contentLength > this.#limits.maxBodyBytes) {
      this.#state = { kind: 'discard', remaining: head.contentLength, status: 413 };
      return this.#pushDiscard(this.#state, rest);
    }
    this.#state = { kind: 'body', head, body: Buffer.allocUnsafe(head.contentLength), received: 0 };
    return this.#pushBody(this.#state, rest);
  }

  #pushBody(state: Extract<ParserState, { kind: 'body' }>, chunk: Buffer): ParseEvent | undefined {
    const take = Math.min(chunk.length, state.body.length - state.received);
    chunk.copy(state.body, state.received, 0, take);
    state.received += take;
    if (state.received < state.body.length) return undefined;
    const { method, target } = state.head;
    return this.#finish({ kind: 'request', request: { method, target, body: state.body } });
  }

  // Reads and throws away the body so the peer sees a clean close rather than
  // a reset when we reply without consuming it.
  #pushDiscard(state: Extract<ParserState, { kind: 'discard' }>, chunk: Buffer): ParseEvent | undefined {
    state.remaining -= Math.min(chunk.length, state.remaining);
    return state.remaining > 0 ? undefined : this.#fail(state.status);
  }
}

/** Writes the full response and half-closes the socket. */
export function writeResponse(socket: Socket, response: Response): void {
  const body = response.body ?? Buffer.alloc(0);
  let head = `HTTP/1.1 ${response.status} ${reasonPhrase(response.status)}\r\n`;
  for (const [name, value] of response.headers) head += `${name}: ${value}\r\n`;
  if (response.status !== 204) head += `Content-Length: ${body.length}\r\n`;
  head += 'Connection: close\r\n\r\n';

  socket.cork();
  socket.write(head, 'latin1');
  if (body.length > 0) socket.write(body);
  socket.end();
  socket.uncork();
}
