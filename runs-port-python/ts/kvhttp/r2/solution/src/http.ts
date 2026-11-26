/** HTTP message types and serialization. */

export const Status = {
  OK: 200,
  CREATED: 201,
  NO_CONTENT: 204,
  BAD_REQUEST: 400,
  NOT_FOUND: 404,
  METHOD_NOT_ALLOWED: 405,
  CONTENT_TOO_LARGE: 413,
  REQUEST_HEADER_FIELDS_TOO_LARGE: 431,
} as const;

export type Status = (typeof Status)[keyof typeof Status];

const REASON_PHRASES: Record<Status, string> = {
  200: "OK",
  201: "Created",
  204: "No Content",
  400: "Bad Request",
  404: "Not Found",
  405: "Method Not Allowed",
  413: "Content Too Large",
  431: "Request Header Fields Too Large",
};

/** An error that maps directly onto an HTTP error response. */
export class HttpError extends Error {
  readonly status: Status;

  constructor(status: Status, options?: ErrorOptions) {
    super(REASON_PHRASES[status], options);
    this.name = "HttpError";
    this.status = status;
  }
}

export interface Request {
  readonly method: string;
  readonly path: string;
  /** Header names are lower-cased. */
  readonly headers: ReadonlyMap<string, string>;
  readonly body: Buffer;
}

export interface Response {
  readonly status: Status;
  readonly body?: Buffer;
  readonly headers?: Readonly<Record<string, string>>;
}

const EMPTY = Buffer.alloc(0);

export function serializeResponse(res: Response): Buffer {
  const body = res.body ?? EMPTY;
  const headers: Record<string, string> = { Connection: "close", ...res.headers };
  if (body.length > 0 && !("Content-Type" in headers)) {
    headers["Content-Type"] = "application/octet-stream";
  }
  headers["Content-Length"] = String(body.length);

  const lines = [`HTTP/1.1 ${res.status} ${REASON_PHRASES[res.status]}`];
  for (const [name, value] of Object.entries(headers)) lines.push(`${name}: ${value}`);
  const head = Buffer.from(`${lines.join("\r\n")}\r\n\r\n`, "latin1");
  return Buffer.concat([head, body]);
}
