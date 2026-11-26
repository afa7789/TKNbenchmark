# notes

The HTTP notes service specified in `SPEC.md` (axum + SQLite via rusqlite/r2d2).

```sh
./build.sh                           # release binary at ./app
NOTES_DB=/tmp/notes.db ./app 8080
cargo test                           # unit and in-process HTTP tests
node check.mjs --cases cases.json    # black-box checks
```

## Layout

| File | Contents |
|---|---|
| `src/main.rs` | arguments, `NOTES_DB`, server startup |
| `src/error.rs` | `ApiError` → `{"error": ...}` responses (400/404/405/500) |
| `src/model.rs` | `Note`, `NoteInput::from_json` (title/body/tags validation), `is_valid_tag` |
| `src/routes/mod.rs` | merges the feature routers, 404/405 fallbacks, `NoteId` extractor (non-positive or non-numeric id → 404) |
| `src/store/mod.rs` | schema, connection pool, `Store::call` (runs a closure on a pooled connection off the async runtime) |
| `src/routes/notes.rs`, `src/store/notes.rs` | core: `/health`, `POST /notes`, `GET /notes/{id}`; shared helpers `read_note`, `note_from_row`, `read_tags`, `insert_tags` |
| `tests/common/mod.rs` | `TestApp`: the router over a temporary database |

## Feature ownership

Each branch edits only its own files; the router merge and module declarations already exist.

| Branch | Endpoints | Files |
|---|---|---|
| `crud` | `PUT`, `DELETE /notes/{id}` | `src/routes/crud.rs`, `src/store/crud.rs`, `tests/crud.rs` |
| `list` | `GET /notes` | `src/routes/list.rs`, `src/store/list.rs`, `tests/list.rs` |
| `stats` | `GET /stats`, `GET /tags` | `src/routes/stats.rs`, `src/store/stats.rs`, `tests/stats.rs` |

Conventions: handlers return `Result<_, ApiError>`; data access is an `impl Store` block of async methods
built on `Store::call`, with writes in `TransactionBehavior::Immediate` transactions. Routers may register
other methods on an existing path (`/notes`, `/notes/{id}`); axum merges them and answers other methods
with 405. Changes to shared files (`Cargo.toml`, `model.rs`, `routes/mod.rs`, `store/mod.rs`) go through
the lead.
