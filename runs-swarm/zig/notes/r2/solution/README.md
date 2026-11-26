# notes

A small notes store over HTTP, backed by SQLite. See `SPEC.md`.

```sh
./build.sh                      # release binary at ./app
NOTES_DB=/tmp/notes.db ./app 8080

zig build                       # debug build at zig-out/bin/app
zig build test                  # unit tests
node check.mjs --cases cases-core.json
```

Requires Zig 0.16.0. SQLite is compiled from the upstream amalgamation that
`build.zig.zon` pins; `zig build` downloads it.

## Layout

| File | Purpose |
|---|---|
| `src/main.zig` | Arguments, `NOTES_DB`, startup; the test root lists every module |
| `src/Server.zig` | Accept loop, one concurrent task per connection, body reading, error mapping |
| `src/router.zig` | **Every** route and method, already wired to its handler |
| `src/web.zig` | `Request`, `Response` and the `json`/`jsonError` helpers |
| `src/model.zig` | `Note`, `NoteInput`, `parseNoteInput` (validation), `isValidTag` |
| `src/sqlite.zig` | Thin wrapper over the SQLite C API (`Db`, `Statement`, `transaction`) |
| `src/Store.zig` | The connection, its mutex (`acquire`/`release`) and the schema migrations |
| `src/api/*.zig` | HTTP handlers: parse the request, call the store, build the response |
| `src/store/*.zig` | Data access (SQL) per feature |

Unexpected errors become a 500 and are logged.

## Parallel work

Each branch only edits the two files it owns; the router, the schema, the
build and the test root already cover every endpoint.

| Branch | Endpoints | Files |
|---|---|---|
| `crud` | `PUT /notes/{id}`, `DELETE /notes/{id}` | `src/api/crud.zig`, `src/store/crud.zig` |
| `list` | `GET /notes` with `tag`, `q`, `after`, `limit` | `src/api/list.zig`, `src/store/list.zig` |
| `stats` | `GET /stats`, `GET /tags` | `src/api/stats.zig`, `src/store/stats.zig` |

Conventions:

- The router has already parsed the `{id}` (a positive integer; anything else is a 404)
  and checked the method (405). Handlers get `(req)` or `(req, id)`.
- Allocate response data from `req.arena`; it is freed after the response is sent.
- Store functions take `*Store`, lock it with `acquire`/`release` and wrap
  multi-statement writes in `db.transaction`. Reuse `store/notes.zig`:
  `fetch`, `scanNote`, `note_columns`, `loadTags`, `insertTags`.
- Validation errors are 400 with `web.jsonError`; reuse `model.parseNoteInput`
  for note bodies.
- Schema: `notes (id AUTOINCREMENT, title, body)` and
  `note_tags (note_id → notes ON DELETE CASCADE, tag)`, indexed by `(tag, note_id)`.
  If a branch needs a schema change, add a new entry to `Store.migrations`,
  never edit an existing one.
- Put unit tests next to the code; `zig build test` already picks them up.
- Check with `node check.mjs --cases cases-<branch>.json`, then `cases.json`.
