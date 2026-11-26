import { type Request, type Response, Status } from "./http.ts";
import type { Store } from "./store.ts";

const KEY_RE = /^[A-Za-z0-9_-]{1,64}$/;
const KV_PREFIX = "/kv/";

/** Routes requests to the key-value store. */
export class App {
  readonly #store: Store;

  constructor(store: Store) {
    this.#store = store;
  }

  handle(req: Request): Response {
    const { path } = req;
    if (path === "/health") {
      if (req.method !== "GET") return methodNotAllowed("GET");
      return {
        status: Status.OK,
        body: Buffer.from("ok"),
        headers: { "Content-Type": "text/plain" },
      };
    }
    if (path === "/kv") {
      if (req.method !== "GET") return methodNotAllowed("GET");
      return {
        status: Status.OK,
        body: Buffer.from(JSON.stringify(this.#store.keys())),
        headers: { "Content-Type": "application/json" },
      };
    }
    if (path.startsWith(KV_PREFIX)) {
      const key = path.slice(KV_PREFIX.length);
      if (!KEY_RE.test(key)) return { status: Status.BAD_REQUEST };
      return this.#handleKey(req, key);
    }
    return { status: Status.NOT_FOUND };
  }

  #handleKey(req: Request, key: string): Response {
    switch (req.method) {
      case "GET": {
        const value = this.#store.get(key);
        return value === undefined ? { status: Status.NOT_FOUND } : { status: Status.OK, body: value };
      }
      case "PUT": {
        const created = this.#store.put(key, req.body);
        return { status: created ? Status.CREATED : Status.OK };
      }
      case "DELETE":
        return { status: this.#store.delete(key) ? Status.NO_CONTENT : Status.NOT_FOUND };
      default:
        return methodNotAllowed("GET, PUT, DELETE");
    }
  }
}

function methodNotAllowed(allow: string): Response {
  return { status: Status.METHOD_NOT_ALLOWED, headers: { Allow: allow } };
}
