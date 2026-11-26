# notes

A small HTTP notes store backed by SQLite, written in Zig 0.16. See `SPEC.md` for the API.

```sh
./build.sh                          # release binary at ./app (fetches dependencies)
NOTES_DB=/tmp/notes.db ./app 8080

zig build                           # debug build at zig-out/bin/notes
zig build test                      # unit tests
zig build run -- 8080               # debug run (set NOTES_DB)
node check.mjs --cases cases-core.json
```

The only dependency is the SQLite amalgamation, pinned in `build.zig.zon`, compiled as a static library,
and bound through `translate-c`. HTTP and JSON come from the standard library.

## Layout

| File | Purpose |
|---|---|
| `src/main.zig` | Entry point: arguments, `NOTES_DB`, starts the server. Root of the unit tests. |
| `src/Server.zig` | Accept loop. Each connection runs concurrently; maps handler errors to 413/500. |
| `src/router.zig` | Route table (all endpoints), path matching, 404 and 405. |
| `src/http/Context.zig` | Per-request context: arena, store, path params, query params, body, responses. |
| `src/http/query.zig` | Query-string parsing and decoding. |
| `src/note.zig` | `Note`, `Input`, and validation of request bodies (title, body, tags). |
| `src/db/sqlite.zig` | Thin wrapper over the SQLite C API (`Db`, `Statement`). |
| `src/db/Store.zig` | The shared connection, serialized by a mutex: `acquire()` / `release()`. |
| `src/db/schema.zig` | Schema migrations (`PRAGMA user_version`). |
| `src/db/notes.zig` | Single-note queries: `insert`, `get`, `exists`, `tagsOf`, `insertTags`. |
| `src/api/*.zig` | Handlers, one module per endpoint group. |

Schema: `notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title, body)` and
`note_tags(note_id REFERENCES notes ON DELETE CASCADE, tag)` with an index on `(tag, note_id)`. Deleting a
note deletes its tags (foreign keys are on). `AUTOINCREMENT` keeps ids from being reused.

## Endpoint modules

Every route is declared in `src/router.zig`. Each endpoint group has a handler module under `src/api/` and,
when it needs its own queries, a matching module under `src/db/`:

| Endpoints | Handlers | Queries |
|---|---|---|
| `POST /notes`, `GET /notes/{id}` | `src/api/notes.zig` | `src/db/notes.zig` |
| `PUT /notes/{id}`, `DELETE /notes/{id}` | `src/api/crud.zig` | `src/db/crud.zig` |
| `GET /notes` with `tag`, `q`, `after`, `limit` | `src/api/list.zig` | `src/db/list.zig` |
| `GET /stats`, `GET /tags` | `src/api/stats.zig` | `src/db/stats.zig` |

Building blocks for handlers:

- `notes.idParam(ctx)` gives the `{id}` as an `i64`. If it is not a positive integer, it answers 404 and
  returns null. `notes.sendNotFound(ctx)` answers 404.
- `notes.readInput(ctx)` reads and validates a `{title, body?, tags?}` body. If it is invalid, it answers
  400 and returns null.
- `ctx.queryParam("limit")` gives the decoded value, or null if the parameter is absent.
- `ctx.sendJson(status, value)`, `ctx.sendError(status, message)` (`{"error": message}`) and
  `ctx.sendEmpty(.no_content)` send responses.
- Database: `const db = ctx.store.acquire(); defer ctx.store.release();`, then use `db.run(sql, args)`,
  `db.prepare(sql)`, `db.begin()`, `errdefer db.rollback()`, `db.commit()` and `db.changes()`. Allocate
  results in `ctx.arena`, and copy column text with `columnTextAlloc`. Keep the lock only for the queries,
  not while you send the response.
- Errors: return `error.Sqlite` or `error.OutOfMemory` and the server logs it and answers 500.

Reference new modules from a module that is already tested (`test { _ = @import(...); }`) so that
`zig build test` picks up their unit tests.
