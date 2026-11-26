import type { Socket } from 'node:net';

export const MAX_HEADER_BYTES = 64 * 1024;
export const MAX_BODY_BYTES = 1024 * 1024;

export interface Request {
  method: string;
  target: string;
  /** Header fields in arrival order; names keep their original case. */
  headers: Array<[name: string, value: string]>;
  body: Buffer;
}

export interface Response {
  status: number;
  contentType?: string;
  body?: Buffer;
}

/** Thrown while reading a request that cannot be served; carries the status to reply with. */
export class HttpError extends Error {
  readonly status: number;

  constructor(status: number) {
    super(`HTTP ${status} ${reasonPhrase(status)}`);
    this.name = 'HttpError';
    this.status = status;
  }
}

const CRLF = Buffer.from('\r\n');
const MAX_SIZE_T = (1n << 64n) - 1n;

/** Strips leading and trailing spaces and tabs (HTTP optional whitespace). */
function trimOws(s: string): string {
  return s.replace(/^[ \t]+|[ \t]+$/g, '');
}

/** Case-insensitive header lookup; returns the first match. */
export function header(request: Request, name: string): string | undefined {
  const wanted = name.toLowerCase();
  return request.headers.find(([k]) => k.toLowerCase() === wanted)?.[1];
}

/** Parses a non-negative integer that must fit in 64 bits; anything else is a 400. */
function parseSize(s: string, radix: 10 | 16): number {
  const pattern = radix === 10 ? /^[0-9]+$/ : /^[0-9A-Fa-f]+$/;
  if (!pattern.test(s)) throw new HttpError(400);
  const value = BigInt(radix === 10 ? s : `0x${s}`);
  if (value > MAX_SIZE_T) throw new HttpError(400);
  // Exact up to 2^53, which is far beyond any size limit we compare against.
  return Number(value);
}

/**
 * Buffered pull-style reader over a socket. Incoming data is queued and the
 * socket is paused until the parser asks for more, giving natural backpressure.
 */
export class SocketReader {
  readonly #socket: Socket;
  #buf: Buffer = Buffer.alloc(0);
  #pos = 0;
  #pending: Buffer[] = [];
  #ended = false;
  #failed = false;
  #wake: (() => void) | undefined;

  readonly #onData = (chunk: Buffer): void => {
    this.#pending.push(chunk);
    this.#socket.pause();
    this.#notify();
  };
  readonly #onEnd = (): void => {
    this.#ended = true;
    this.#notify();
  };
  readonly #onFailure = (): void => {
    this.#failed = true;
    this.#notify();
  };

  constructor(socket: Socket) {
    this.#socket = socket;
    socket.on('data', this.#onData);
    socket.on('end', this.#onEnd);
    socket.on('error', this.#onFailure);
    socket.on('timeout', this.#onFailure);
  }

  /** Detaches from the socket so the caller can take over its events. */
  release(): void {
    this.#socket.off('data', this.#onData);
    this.#socket.off('end', this.#onEnd);
    this.#socket.off('error', this.#onFailure);
    this.#socket.off('timeout', this.#onFailure);
  }

  get #available(): number {
    return this.#buf.length - this.#pos;
  }

  #notify(): void {
    const wake = this.#wake;
    this.#wake = undefined;
    wake?.();
  }

  /** Reads more bytes into the buffer; resolves false on EOF. */
  async fill(): Promise<boolean> {
    for (;;) {
      if (this.#pending.length > 0) {
        this.#buf = Buffer.concat([this.#buf.subarray(this.#pos), ...this.#pending]);
        this.#pos = 0;
        this.#pending = [];
        return true;
      }
      if (this.#failed) throw new HttpError(408); // timeout or connection error
      if (this.#ended) return false;
      const { promise, resolve } = Promise.withResolvers<void>();
      this.#wake = resolve;
      this.#socket.resume();
      await promise;
    }
  }

  /** Returns the next CRLF-terminated line (without terminator), decoded as latin1. */
  async readLine(limit: number): Promise<string> {
    for (;;) {
      const end = this.#buf.indexOf(CRLF, this.#pos);
      if (end >= 0) {
        const line = this.#buf.toString('latin1', this.#pos, end);
        this.#pos = end + CRLF.length;
        return line;
      }
      if (this.#available > limit) throw new HttpError(431);
      if (!(await this.fill())) throw new HttpError(400);
    }
  }

  async readExact(n: number): Promise<Buffer> {
    while (this.#available < n) {
      if (!(await this.fill())) throw new HttpError(400);
    }
    const out = Buffer.from(this.#buf.subarray(this.#pos, this.#pos + n));
    this.#pos += n;
    return out;
  }
}

async function readChunkedBody(reader: SocketReader): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let total = 0;
  for (;;) {
    const line = await reader.readLine(MAX_HEADER_BYTES);
    const semi = line.indexOf(';');
    const size = parseSize(trimOws(semi >= 0 ? line.slice(0, semi) : line), 16);
    if (size === 0) break;
    if (size > MAX_BODY_BYTES || total + size > MAX_BODY_BYTES) throw new HttpError(413);
    chunks.push(await reader.readExact(size));
    total += size;
    if ((await reader.readLine(0)) !== '') throw new HttpError(400);
  }
  // Trailer section, terminated by an empty line.
  let trailerBytes = 0;
  for (;;) {
    const line = await reader.readLine(MAX_HEADER_BYTES);
    if (line === '') break;
    trailerBytes += line.length;
    if (trailerBytes > MAX_HEADER_BYTES) throw new HttpError(431);
  }
  return Buffer.concat(chunks, total);
}

/**
 * Reads one request. Resolves undefined if the peer closed the connection
 * before sending anything; rejects with HttpError on malformed input.
 */
export async function readRequest(reader: SocketReader): Promise<Request | undefined> {
  if (!(await reader.fill())) return undefined;

  let requestLine = await reader.readLine(MAX_HEADER_BYTES);
  // Tolerate stray blank lines before the request line (RFC 9112 §2.2).
  while (requestLine === '') requestLine = await reader.readLine(MAX_HEADER_BYTES);
  let headerBytes = requestLine.length;

  const sp1 = requestLine.indexOf(' ');
  const sp2 = sp1 < 0 ? -1 : requestLine.indexOf(' ', sp1 + 1);
  if (sp2 < 0 || sp1 === 0 || sp2 === sp1 + 1) throw new HttpError(400);
  if (!requestLine.startsWith('HTTP/', sp2 + 1)) throw new HttpError(400);

  const request: Request = {
    method: requestLine.slice(0, sp1),
    target: requestLine.slice(sp1 + 1, sp2),
    headers: [],
    body: Buffer.alloc(0),
  };

  for (;;) {
    const line = await reader.readLine(MAX_HEADER_BYTES);
    if (line === '') break;
    headerBytes += line.length;
    if (headerBytes > MAX_HEADER_BYTES) throw new HttpError(431);
    const colon = line.indexOf(':');
    if (colon <= 0) throw new HttpError(400);
    request.headers.push([line.slice(0, colon), trimOws(line.slice(colon + 1))]);
  }

  const transferEncoding = header(request, 'Transfer-Encoding');
  const contentLength = header(request, 'Content-Length');
  if (transferEncoding !== undefined) {
    if (trimOws(transferEncoding).toLowerCase() !== 'chunked') throw new HttpError(501);
    request.body = await readChunkedBody(reader);
  } else if (contentLength !== undefined) {
    const length = parseSize(trimOws(contentLength), 10);
    if (length > MAX_BODY_BYTES) throw new HttpError(413);
    request.body = await reader.readExact(length);
  }
  return request;
}

const REASON_PHRASES: Readonly<Record<number, string>> = {
  200: 'OK',
  201: 'Created',
  204: 'No Content',
  400: 'Bad Request',
  404: 'Not Found',
  405: 'Method Not Allowed',
  408: 'Request Timeout',
  413: 'Content Too Large',
  431: 'Request Header Fields Too Large',
  500: 'Internal Server Error',
  501: 'Not Implemented',
};

export function reasonPhrase(status: number): string {
  return REASON_PHRASES[status] ?? 'Unknown';
}

/** Serialises a response, always with Content-Length (except 204) and Connection: close. */
export function serializeResponse(response: Response): Buffer {
  const body = response.body ?? Buffer.alloc(0);
  let head = `HTTP/1.1 ${response.status} ${reasonPhrase(response.status)}\r\n`;
  if (response.contentType) head += `Content-Type: ${response.contentType}\r\n`;
  // 204 must not carry a body or Content-Length framing; everything else
  // advertises its exact length.
  if (response.status !== 204) head += `Content-Length: ${body.length}\r\n`;
  head += 'Connection: close\r\n\r\n';
  return Buffer.concat([Buffer.from(head, 'latin1'), body]);
}
