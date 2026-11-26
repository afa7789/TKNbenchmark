# notes

The HTTP notes service specified in [SPEC.md](SPEC.md), in Go with SQLite
(`modernc.org/sqlite`, pure Go, no cgo).

```sh
./build.sh                       # release binary at ./app
NOTES_DB=/tmp/notes.db ./app 8080
go test ./...                    # unit tests
node check.mjs --cases cases-core.json
```

## Layout

| Path | Contents |
|---|---|
| `main.go` | flags, env, listener, graceful shutdown |
| `internal/note` | `Note` model, `ParseInput` validation for POST/PUT bodies, tag rules |
| `internal/store/store.go` | connection, schema, shared helpers (`selectNotes`, `scanNote`, `inTx`, `insertTags`) |
| `internal/store/notes.go` | `Create`, `Get` |
| `internal/httpapi/server.go` | `Server`, the complete routing table, JSON bodies for 404/405 |
| `internal/httpapi/respond.go` | `writeJSON`, `writeError`, `serverError`, `notFound`, `noteID`, `readInput` |
| `internal/httpapi/notes.go` | `POST /notes`, `GET /notes/{id}` |
| `internal/httpapi/crud.go` | `PUT /notes/{id}`, `DELETE /notes/{id}` |
| `internal/httpapi/list.go` | `GET /notes` with `tag`, `q`, `after`, `limit` |
| `internal/httpapi/stats.go` | `GET /stats`, `GET /tags` |
| `internal/store/crud.go`, `list.go`, `stats.go` | `Update`, `Delete`; `List`; `Stats`, `TagCounts` |
| `internal/httpapi/helpers_test.go` | `newTestServer`, `do`, `assertJSON`, `assertError` for HTTP tests |

Schema: `notes(id AUTOINCREMENT, title, body)` and `note_tags(note_id, tag)`,
with `ON DELETE CASCADE` and an index on `(tag, note_id)`. Ids are never reused.

## Conventions

- Use `s.noteID` for `{id}` (an invalid id gives 404) and `s.readInput` for
  `{title, body?, tags?}` bodies (an invalid body gives 400).
- Map `store.ErrNotFound` to `s.notFound(w)`. Send any other error to
  `s.serverError(w, r, err)`.
- Read notes with `selectNotes` + `scanNote`, so each note and its tags come
  from the same snapshot. Run writes through `s.inTx`, which opens a
  `BEGIN IMMEDIATE` transaction.
