# notes

The HTTP notes service specified in [SPEC.md](SPEC.md): axum + SQLite (rusqlite, bundled, pooled with r2d2).

```sh
./build.sh                       # release binary at ./app
NOTES_DB=/tmp/notes.db ./app 8080
cargo test                       # unit + in-process integration tests
node check.mjs                    # all examples (or --cases cases-<feature>.json)
```

## Layout and ownership

Each feature has its own files, already declared and wired into the router, so feature branches
do not need to edit shared files:

| Branch  | Endpoints                              | Edit only                                                 | Check with              |
|---------|----------------------------------------|-----------------------------------------------------------|-------------------------|
| (core)  | `/health`, `POST /notes`, `GET /notes/{id}` | `routes/{health,notes}.rs`, `db/{mod,schema,notes}.rs`, `model.rs`, `extract.rs`, `error.rs` | `cases-core.json`  |
| `crud`  | `PUT /notes/{id}`, `DELETE /notes/{id}` | `src/routes/crud.rs`, `src/db/crud.rs`, `tests/crud.rs`   | `cases-crud.json`       |
| `list`  | `GET /notes?tag&q&after&limit`         | `src/routes/list.rs`, `src/db/list.rs`, `tests/list.rs`   | `cases-list.json`       |
| `stats` | `GET /stats`, `GET /tags`              | `src/routes/stats.rs`, `src/db/stats.rs`, `tests/stats.rs`| `cases-stats.json`      |

Conventions:

- `routes/<feature>.rs` exposes `routes() -> Router<AppState>`; `routes/mod.rs` merges them. Two
  modules may register the same path with different methods (`/notes` has `POST` in `notes.rs` and
  `GET` in `list.rs`). Unknown paths answer 404 and unsupported methods 405, both handled centrally.
- Handlers return `ApiResult<T>`; errors are `ApiError` (`BadRequest(msg)` → 400, `NotFound` → 404),
  answered as `{"error": "..."}`.
- Extractors: `NoteId` (the `{id}` segment; non-positive or non-numeric ids → 404) and `NoteInput`
  (the validated `{title, body?, tags?}` body; put it last in the handler's arguments).
- Data access is synchronous functions over `&Connection` / `&mut Connection` in `db/<feature>.rs`,
  called through `state.db.run(move |conn| ...)`. Use `TransactionBehavior::Immediate` for
  transactions that write. Reuse `db::notes::{get, tags_of, replace_tags}`.
- Schema: `notes(id AUTOINCREMENT, title, body)` and `note_tags(note_id → notes ON DELETE CASCADE,
  tag)`, indexed by `(tag, note_id)`. A schema change is a new entry in `db/schema.rs::MIGRATIONS`;
  coordinate it with the lead first.
- Integration tests: create `tests/<feature>.rs` starting with `mod common;` and use
  `common::TestApp` (`get`, `post`, `request`, `create`, `restart`).
