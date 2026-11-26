//! HTTP routing. Each feature module exposes `routes()`, merged here; routes for the same path
//! from different modules (for example `GET` and `PUT /notes/{id}`) are combined by method.

mod crud;
mod health;
mod list;
mod notes;
mod stats;

use axum::Router;

use crate::AppState;
use crate::error::ApiError;

/// The complete application.
pub fn router(state: AppState) -> Router {
    Router::new()
        .merge(health::routes())
        .merge(notes::routes())
        .merge(crud::routes())
        .merge(list::routes())
        .merge(stats::routes())
        .fallback(async || ApiError::NotFound)
        .method_not_allowed_fallback(async || ApiError::MethodNotAllowed)
        .with_state(state)
}
