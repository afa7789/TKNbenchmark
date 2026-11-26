//! A small notes store over HTTP, backed by SQLite.

pub mod error;
pub mod model;
pub mod routes;
pub mod store;

pub use routes::{AppState, router};
pub use store::Store;
