# notes

A small notes store over HTTP, backed by SQLite. See [SPEC.md](SPEC.md).

    ./build.sh                          # optimized release binary at ./app
    NOTES_DB=/tmp/notes.db ./app 8080   # serve on 127.0.0.1:8080

Development:

    go build -o app ./cmd/notes   # debug build
    go test ./...
    node check.mjs --no-build --cases cases-core.json

## Layout

| Path | Contents |
|---|---|
| `cmd/notes` | `main`: arguments, environment, server lifecycle |
| `internal/note` | the `Note` type and the validation and normalization of note content (`Input.Normalize`) |
| `internal/store` | SQLite storage: `store.go` (connection, schema, `inTx`), `notes.go` (`Create`, `Get`, shared tag helpers), one file per feature |
| `internal/server` | HTTP API: `routes.go` (all endpoints), `respond.go` (JSON and error helpers), one file per feature |

The SQLite driver is `modernc.org/sqlite` (pure Go, no cgo).

## Conventions

Every route is registered in `internal/server/routes.go`; a request that matches no route gets a JSON
404, or a JSON 405 with an `Allow` header. Each feature has its own handler file in `internal/server` and
query file in `internal/store`:

| Feature | Endpoints | Files |
|---|---|---|
| core | `GET /health`, `POST /notes`, `GET /notes/{id}` | `health.go`, `notes.go` |
| crud | `PUT`, `DELETE /notes/{id}` | `crud.go` |
| list | `GET /notes` and its query parameters | `list.go` |
| stats | `GET /stats`, `GET /tags` | `stats.go` |

What to reuse:

- Handlers: `noteID(r)` for the `{id}` path value (not ok → `s.writeNotFound`), `decodeNoteInput(w, r)` for a
  `{title, body?, tags?}` body, `badRequest(...)` for invalid query parameters, `s.writeErr` to answer any
  error (`store.ErrNotFound` → 404, `*requestError` and `*note.ValidationError` → 400, else 500),
  `s.writeJSON` for success and `w.WriteHeader(http.StatusNoContent)` for an empty one.
- Store: `s.inTx` for multi-statement writes, `s.inReadTx` for consistent multi-query reads, `replaceTags` to set a note's tags, `attachTags` to load the
  tags of a page of notes in one query, `newNote` to build a note from its id and normalized input. Return
  `ErrNotFound` for a missing note. Tags live in `note_tags (note_id, tag)`, deleted with their note by
  `ON DELETE CASCADE`; ids come from `AUTOINCREMENT` and are never reused.
- Tests: `newTestServer`, `do`, `wantStatus`, `wantJSON`, `wantError` and `mustCreate` (server);
  `openTest` and `mustCreate` (store).
