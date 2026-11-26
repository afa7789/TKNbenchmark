//! HTTP handlers, one submodule per feature. Each submodule exposes `routes()`, merged in
//! [`crate::app::router`]. Several features may register different methods on the same path
//! (e.g. `GET` and `POST /notes`); axum merges them, and answers other methods with 405.

pub mod crud;
pub mod extract;
pub mod list;
pub mod notes;
pub mod stats;
