import type { Socket } from "node:net";

/** The stream ended before the requested data arrived. */
export class IncompleteReadError extends Error {
  readonly partial: Buffer;

  constructor(partial: Buffer) {
    super(`stream ended after ${partial.length} bytes`);
    this.name = "IncompleteReadError";
    this.partial = partial;
  }
}

/** A separator was not found within the allowed number of bytes. */
export class LimitOverrunError extends Error {
  constructor(limit: number) {
    super(`separator not found within ${limit} bytes`);
    this.name = "LimitOverrunError";
  }
}

const EMPTY = Buffer.alloc(0);

/**
 * Pull-based buffered reader over a socket. The socket is kept paused except
 * while the reader is waiting for more data, so a slow consumer applies
 * backpressure instead of buffering unbounded input.
 */
export class StreamReader {
  readonly #socket: Socket;
  #buffer: Buffer = EMPTY;
  #ended = false;
  #error: Error | undefined;
  #wake: (() => void) | undefined;

  constructor(socket: Socket) {
    this.#socket = socket;
    socket.pause();
    socket.on("data", (chunk: Buffer) => {
      this.#buffer = this.#buffer.length === 0 ? chunk : Buffer.concat([this.#buffer, chunk]);
      socket.pause();
      this.#notify();
    });
    socket.on("end", () => {
      this.#ended = true;
      this.#notify();
    });
    socket.on("error", (err) => {
      this.#error = err;
      this.#notify();
    });
  }

  /** Reads up to and including `separator`, which must appear within `limit` bytes. */
  async readUntil(separator: Buffer, limit: number): Promise<Buffer> {
    let searchFrom = 0;
    for (;;) {
      const index = this.#buffer.indexOf(separator, searchFrom);
      if (index >= 0) {
        const end = index + separator.length;
        if (end > limit) throw new LimitOverrunError(limit);
        return this.#take(end);
      }
      if (this.#buffer.length > limit) throw new LimitOverrunError(limit);
      searchFrom = Math.max(0, this.#buffer.length - separator.length + 1);
      if (!(await this.#fill())) throw new IncompleteReadError(this.#take(this.#buffer.length));
    }
  }

  /** Reads exactly `n` bytes. */
  async readExactly(n: number): Promise<Buffer> {
    const parts: Buffer[] = [];
    let remaining = n;
    while (remaining > 0) {
      if (this.#buffer.length === 0 && !(await this.#fill())) {
        throw new IncompleteReadError(Buffer.concat(parts));
      }
      const part = this.#take(Math.min(remaining, this.#buffer.length));
      parts.push(part);
      remaining -= part.length;
    }
    return parts.length === 1 ? parts[0]! : Buffer.concat(parts, n);
  }

  /** Reads and drops exactly `n` bytes. */
  async discard(n: number): Promise<void> {
    let remaining = n;
    while (remaining > 0) {
      if (this.#buffer.length === 0 && !(await this.#fill())) {
        throw new IncompleteReadError(EMPTY);
      }
      remaining -= this.#take(Math.min(remaining, this.#buffer.length)).length;
    }
  }

  #take(n: number): Buffer {
    const out = this.#buffer.subarray(0, n);
    this.#buffer = this.#buffer.subarray(n);
    return out;
  }

  /** Waits for more input; resolves false at end of stream. */
  async #fill(): Promise<boolean> {
    const before = this.#buffer.length;
    while (this.#buffer.length === before) {
      if (this.#error) throw this.#error;
      if (this.#ended) return false;
      await new Promise<void>((resolve) => {
        this.#wake = resolve;
        this.#socket.resume();
      });
    }
    return true;
  }

  #notify(): void {
    const wake = this.#wake;
    this.#wake = undefined;
    wake?.();
  }
}
