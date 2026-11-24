# kvhttp

An HTTP/1.1 key-value server — the kind of backend a React or Vue front end talks to.

`./app <port>` listens on `127.0.0.1:<port>` and serves until killed. It must accept connections
within 2 seconds of starting. Data lives in memory.

- A **key** matches `[A-Za-z0-9_-]{1,64}`. A **value** is any byte sequence up to 1 MiB.
- Requests carry a `Content-Length` when they have a body. Clients send `Connection: close`;
  handling one request per connection is enough. Every response must carry a correct
  `Content-Length` (or close the connection right after the body).
- The server must handle at least 64 simultaneous connections correctly.

Routes:

| Request | Response |
|---|---|
| `GET /health` | `200`, body `ok` |
| `PUT /kv/<key>` with the value as body | `201` if the key was new, `200` if it replaced a value; empty body |
| `GET /kv/<key>` | `200` with the exact stored bytes; `404` if absent |
| `DELETE /kv/<key>` | `204` if deleted; `404` if absent |
| `GET /kv` | `200`, `Content-Type: application/json`, a JSON array of every key sorted ascending, e.g. `["a","b"]` |

Errors:

- `/kv/<rest>` where `<rest>` is not a valid key (empty, too long, a `/`, another character) → `400`.
- Any other path → `404`.
- A route above with a method it does not list (e.g. `POST /health`, `PATCH /kv/a`) → `405`.

Request paths in the tests never carry a query string.
