# notes

A small notes store over HTTP, backed by SQLite. See [SPEC.md](SPEC.md).

```sh
./build.sh                          # optimized binary at ./app
NOTES_DB=/tmp/notes.db ./app 8080

zig build                           # debug build at zig-out/bin/notes
zig build test                      # unit tests
zig build run -- 8080               # debug run (set NOTES_DB)
node check.mjs --cases cases-core.json
```

Requires Zig 0.16.0. SQLite is built from the official amalgamation, which
`zig build` fetches as declared in `build.zig.zon`.

## Layout

| File | Purpose |
|---|---|
| `src/main.zig` | Arguments, environment, startup |
| `src/server.zig` | HTTP/1.1 transport: accept loop, one concurrent task per connection, body limits |
| `src/router.zig` | Path and method → handler; 404 and 405 |
| `src/api.zig` | `Request`, `Response` (JSON helpers) and the per-request `Context` |
| `src/note.zig` | The `Note` type and validation of `{title, body?, tags?}` |
| `src/query.zig` | URL query string parsing |
| `src/db/sqlite.zig` | Thin binding over the SQLite C API (`Conn`, `Stmt`) |
| `src/db/Pool.zig` | Connection pool (WAL mode, busy timeout) |
| `src/db/schema.zig` | Schema and migrations (`PRAGMA user_version`) |
| `src/store/notes.zig` | Queries for single notes and shared tag helpers |
| `src/store/crud.zig` | Replacing and deleting notes |
| `src/store/list.zig` | Listing notes with filters |
| `src/store/stats.zig` | Note and tag counts |
| `src/handlers/notes.zig` | `POST /notes`, `GET /notes/{id}` |
| `src/handlers/crud.zig` | `PUT /notes/{id}`, `DELETE /notes/{id}` |
| `src/handlers/list.zig` | `GET /notes` with `tag`, `q`, `after`, `limit` |
| `src/handlers/stats.zig` | `GET /stats`, `GET /tags` |
| `src/TestEnv.zig` | Test helper: in-memory database, requests through the router |

Handlers get a `*const api.Context` (request arena, database pool) and an
`api.Request`, and return an `api.Response`; they never touch HTTP directly, so
they are unit-tested through `TestEnv` without sockets.

Conventions:

- Validate note input with `note.parseInput` (map errors with
  `note.errorMessage`); load notes and tags with `store/notes.zig` (`get`,
  `tagsOf`, `insertTags`).
- Writes run in `conn.begin(.immediate)` … `conn.commit()` with
  `errdefer conn.rollback()`; acquire one connection per request.
- To change the schema, append a migration to `src/db/schema.zig` rather than
  editing an existing one.
- `node check.mjs` runs every example in `cases.json`; `--cases
  cases-<feature>.json` runs one feature's examples.
