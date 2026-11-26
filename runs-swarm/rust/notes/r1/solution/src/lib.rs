//! A small notes store over HTTP, backed by SQLite.
//!
//! Layout (one feature per file so features can be developed independently):
//! - [`note`]: the domain model and input validation.
//! - [`store`]: the SQLite pool, schema, and data access, one submodule per feature.
//! - [`api`]: HTTP handlers, one submodule per feature, each exposing `routes()`.
//! - [`app`]: assembles the router and runs the server.

pub mod api;
pub mod app;
pub mod error;
pub mod note;
pub mod store;
