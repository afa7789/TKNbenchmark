import { HttpError, type Request, Status } from "./http.ts";
import { IncompleteReadError, LimitOverrunError, type StreamReader } from "./reader.ts";

export const MAX_VALUE_SIZE = 1024 * 1024;
export const MAX_HEADER_SIZE = 64 * 1024;

const HEAD_END = Buffer.from("\r\n\r\n");
const CRLF = Buffer.from("\r\n");
const DISCARD_CHUNK = 64 * 1024;
const DIGITS_RE = /^[0-9]+$/;
const HEX_RE = /^[0-9A-Fa-f]+$/;

/** Reads one request; returns null if the client closed without sending anything. */
export async function readRequest(reader: StreamReader): Promise<Request | null> {
  let head: string;
  try {
    head = (await reader.readUntil(HEAD_END, MAX_HEADER_SIZE)).toString("latin1");
  } catch (err) {
    if (err instanceof IncompleteReadError) {
      if (err.partial.toString("latin1").trim() === "") return null;
      throw new HttpError(Status.BAD_REQUEST, { cause: err });
    }
    if (err instanceof LimitOverrunError) {
      throw new HttpError(Status.REQUEST_HEADER_FIELDS_TOO_LARGE, { cause: err });
    }
    throw err;
  }

  const [requestLine = "", ...headerLines] = head.split("\r\n");
  const parts = requestLine.split(" ");
  if (parts.length !== 3) throw new HttpError(Status.BAD_REQUEST);
  const [method, target] = parts as [string, string, string];

  const headers = new Map<string, string>();
  for (const line of headerLines) {
    if (line === "") continue;
    const colon = line.indexOf(":");
    if (colon < 0) throw new HttpError(Status.BAD_REQUEST);
    headers.set(line.slice(0, colon).trim().toLowerCase(), line.slice(colon + 1).trim());
  }

  const path = target.split("?", 1)[0]!;
  const body = await readBody(reader, headers);
  return { method, path, headers, body };
}

async function readBody(reader: StreamReader, headers: ReadonlyMap<string, string>): Promise<Buffer> {
  if ((headers.get("transfer-encoding") ?? "").toLowerCase().includes("chunked")) {
    return readChunked(reader);
  }
  const rawLength = headers.get("content-length");
  if (rawLength === undefined) return Buffer.alloc(0);
  if (!DIGITS_RE.test(rawLength)) throw new HttpError(Status.BAD_REQUEST);
  const length = Number(rawLength);
  try {
    if (length > MAX_VALUE_SIZE) {
      // Drain the body so the client reliably receives the error response.
      await discardAll(reader, length);
      throw new HttpError(Status.CONTENT_TOO_LARGE);
    }
    return await reader.readExactly(length);
  } catch (err) {
    if (err instanceof IncompleteReadError) throw new HttpError(Status.BAD_REQUEST, { cause: err });
    throw err;
  }
}

async function discardAll(reader: StreamReader, length: number): Promise<void> {
  for (let remaining = length; remaining > 0; remaining -= DISCARD_CHUNK) {
    await reader.discard(Math.min(remaining, DISCARD_CHUNK));
  }
}

async function readChunked(reader: StreamReader): Promise<Buffer> {
  const parts: Buffer[] = [];
  let total = 0;
  try {
    for (;;) {
      const sizeLine = (await reader.readUntil(CRLF, MAX_HEADER_SIZE)).toString("latin1");
      const sizeField = sizeLine.split(";", 1)[0]!.trim();
      if (!HEX_RE.test(sizeField)) throw new HttpError(Status.BAD_REQUEST);
      const size = Number.parseInt(sizeField, 16);
      if (size === 0) {
        // Consume optional trailers up to the terminating blank line.
        while ((await reader.readUntil(CRLF, MAX_HEADER_SIZE)).length !== CRLF.length);
        return Buffer.concat(parts, total);
      }
      if (total + size > MAX_VALUE_SIZE) throw new HttpError(Status.CONTENT_TOO_LARGE);
      parts.push(await reader.readExactly(size));
      total += size;
      await reader.readExactly(CRLF.length);
    }
  } catch (err) {
    if (err instanceof IncompleteReadError || err instanceof LimitOverrunError) {
      throw new HttpError(Status.BAD_REQUEST, { cause: err });
    }
    throw err;
  }
}
