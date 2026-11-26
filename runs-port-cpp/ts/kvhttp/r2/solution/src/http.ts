export interface Request {
  readonly method: string;
  readonly path: string;
  readonly body: Buffer;
}

export interface Response {
  readonly status: number;
  readonly headers?: Readonly<Record<string, string>>;
  readonly body?: Buffer | string;
}

export type Handler = (request: Request) => Response;

export const emptyResponse = (status: number): Response => ({ status });

export const textResponse = (status: number, body: string): Response => ({
  status,
  headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  body,
});
