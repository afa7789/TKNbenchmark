//! HTTP routing. Each submodule owns the endpoints of one feature and exposes a `router()`;
//! [`router`] merges them. Routers may share a path as long as they use different methods
//! (e.g. `GET /notes/{id}` here and `PUT /notes/{id}` in `crud`).

mod crud;
mod list;
mod notes;
mod stats;

use axum::Router;
use axum::extract::{FromRequestParts, Path};
use axum::http::request::Parts;

use crate::error::ApiError;
use crate::store::Store;

/// State shared by all handlers.
#[derive(Clone)]
pub struct AppState {
    pub store: Store,
}

/// The complete application router.
pub fn router(state: AppState) -> Router {
    Router::new()
        .merge(notes::router())
        .merge(crud::router())
        .merge(list::router())
        .merge(stats::router())
        .fallback(async || ApiError::NotFound)
        .method_not_allowed_fallback(async || ApiError::MethodNotAllowed)
        .with_state(state)
}

/// The `{id}` path segment of `/notes/{id}`. Anything but a positive decimal integer is a 404,
/// since no note can have that id.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NoteId(pub i64);

impl<S: Send + Sync> FromRequestParts<S> for NoteId {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let Path(raw) = Path::<String>::from_request_parts(parts, state)
            .await
            .map_err(|_| ApiError::NotFound)?;
        parse_note_id(&raw).map(NoteId).ok_or(ApiError::NotFound)
    }
}

fn parse_note_id(raw: &str) -> Option<i64> {
    if raw.is_empty() || !raw.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    raw.parse().ok().filter(|&id| id > 0)
}

#[cfg(test)]
mod tests {
    use super::parse_note_id;

    #[test]
    fn note_ids() {
        assert_eq!(parse_note_id("1"), Some(1));
        assert_eq!(parse_note_id("42"), Some(42));
        assert_eq!(parse_note_id(&i64::MAX.to_string()), Some(i64::MAX));
        for raw in [
            "",
            "0",
            "-1",
            "+1",
            "abc",
            "1.5",
            " 1",
            "99999999999999999999",
        ] {
            assert_eq!(parse_note_id(raw), None, "{raw:?}");
        }
    }
}
