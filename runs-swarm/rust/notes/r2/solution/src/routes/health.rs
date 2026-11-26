//! `GET /health`.

use axum::Router;
use axum::routing::get;

use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new().route("/health", get(async || "ok"))
}
