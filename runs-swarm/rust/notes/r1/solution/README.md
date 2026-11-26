# notes

The HTTP notes service specified in [SPEC.md](SPEC.md): axum + tokio, SQLite through rusqlite
(bundled) with an r2d2 connection pool.

```sh
./build.sh                          # release binary at ./app
NOTES_DB=/tmp/notes.db ./app 8080   # RUST_LOG=debug for more logs
cargo test                          # unit + in-process HTTP tests
node check.mjs --cases cases-core.json
```

## Layout

| Path | Contents |
|---|---|
| `src/main.rs` | CLI (`app <port>`, `NOTES_DB`), logging, startup |
| `src/app.rs` | router assembly (merges every feature's `routes()`), JSON 404/405 fallbacks, graceful shutdown |
| `src/error.rs` | `ApiError` → `{"error": "..."}` with the right status |
| `src/note.rs` | `Note`, `NoteId`, `NoteInput` and all input validation |
| `src/api/extract.rs` | extractors: `NoteInput` (JSON body → 400) and `NoteId` (path `{id}` → 404) |
| `src/store/mod.rs` | `Db` (pool, `Db::call` runs a closure on the blocking pool), schema migrations |
| `src/api/<feature>.rs` | HTTP handlers of a feature, exposing `pub fn routes() -> Router<Db>` |
| `src/store/<feature>.rs` | SQL for a feature: sync functions over `&Connection` / `&mut Connection` |
| `tests/common/mod.rs` | `TestApp`: the router over a temp database, request helpers |
| `tests/<feature>.rs` | HTTP tests of a feature |

## Feature ownership

Each feature lives in its own files, already declared and wired into the router, so branches do
not touch the same files:

| Branch | Endpoints | Files |
|---|---|---|
| core (`main`) | `GET /health`, `POST /notes`, `GET /notes/{id}` | `src/api/notes.rs`, `src/store/notes.rs`, `tests/core.rs` |
| `crud` | `PUT /notes/{id}`, `DELETE /notes/{id}` | `src/api/crud.rs`, `src/store/crud.rs`, `tests/crud.rs` |
| `list` | `GET /notes` with `tag`, `q`, `after`, `limit` | `src/api/list.rs`, `src/store/list.rs`, `tests/list.rs` |
| `stats` | `GET /stats`, `GET /tags` | `src/api/stats.rs`, `src/store/stats.rs`, `tests/stats.rs` |

Several features register methods on the same path (`POST`/`GET /notes`,
`GET`/`PUT`/`DELETE /notes/{id}`); axum merges them and answers other methods with 405.

Conventions:

- Return `ApiResult<T>` from handlers; use `ApiError::bad_request(..)`, `ApiError::NotFound`, and
  `?` on `StoreError` (logged, 500).
- Take `NoteInput` / `NoteId` as handler arguments to get validation and the 400/404 rules for free.
- Run SQL via `db.call(move |conn| store::<feature>::fn(conn, ..)).await?`. Open write transactions
  with `TransactionBehavior::Immediate`. Reuse `store::notes::{get, tags_of, insert_tags}`.
- Tags live in `note_tags(note_id, tag)` with `ON DELETE CASCADE`, indexed by `(tag, note_id)`.
- Shared files (`note.rs`, `error.rs`, `store/mod.rs`, `app.rs`, `Cargo.toml`) belong to core:
  if a feature needs a change there, raise it rather than editing it on a feature branch.
