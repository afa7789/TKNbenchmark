# notes

HTTP notes service backed by SQLite (see SPEC.md). `./build.sh` builds `./app`;
run with `NOTES_DB=/path/to/notes.db ./app <port>`.

## Layout

- `cmd/notes` — entry point (flags, server lifecycle).
- `internal/store` — SQLite storage. `store.go` has the schema and helpers
  (`withTx`, `withReadTx`, `querier`), `notes.go` has Create/Get and the tag helpers
  `insertTags` and `attachTags`.
- `internal/api` — HTTP handlers. `server.go` registers every route and
  answers unmatched requests (404/405) with JSON;
  `input.go` validates note bodies (`decodeNoteInput`, `ValidTag`,
  `parseNoteID`); `respond.go` writes JSON and errors; `notes.go` has
  POST /notes, GET /notes/{id}, `noteID` and `writeStoreError`.

Further endpoints live in their own files in both packages:

| File | Endpoints |
|---|---|
| `crud.go`  | PUT, DELETE /notes/{id} |
| `list.go`  | GET /notes |
| `stats.go` | GET /stats, GET /tags |

Checks: `go test -race ./...` and `node check.mjs` (all examples; use
`--cases cases-<area>.json` for one area).
