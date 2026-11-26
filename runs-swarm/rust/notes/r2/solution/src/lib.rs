//! A small notes store: an HTTP API over a SQLite database.
//!
//! Layout (one file per feature so that features can be developed in parallel):
//!
//! | Feature                         | HTTP handlers         | Data access        |
//! |---------------------------------|-----------------------|--------------------|
//! | `/health`                       | `routes/health.rs`    |                    |
//! | `POST /notes`, `GET /notes/{id}`| `routes/notes.rs`     | `db/notes.rs`      |
//! | `PUT`/`DELETE /notes/{id}`      | `routes/crud.rs`      | `db/crud.rs`       |
//! | `GET /notes` (query params)     | `routes/list.rs`      | `db/list.rs`       |
//! | `GET /stats`, `GET /tags`       | `routes/stats.rs`     | `db/stats.rs`      |
//!
//! Shared building blocks: [`model`] (the note type and input validation), [`extract`] (request
//! extractors), [`error`] (the API error type) and [`db`] (connection pool and schema).

pub mod db;
pub mod error;
pub mod extract;
pub mod model;
pub mod routes;

pub use db::Db;
pub use routes::router;

/// State shared by all request handlers.
#[derive(Clone)]
pub struct AppState {
    pub db: Db,
}
