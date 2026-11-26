//! Request extractors shared by the handlers.
//!
//! - [`NoteInput`] reads and validates a `{title, body?, tags?}` JSON body. It does not require a
//!   `Content-Type` header, and every failure is a 400 with a JSON error body.
//! - [`NoteId`] reads the `{id}` path parameter; anything but a positive integer is a 404.

use axum::body::Bytes;
use axum::extract::{FromRequest, FromRequestParts, Path, Request};
use axum::http::request::Parts;

use crate::error::ApiError;
use crate::note::{NoteId, NoteInput};

impl<S: Send + Sync> FromRequest<S> for NoteInput {
    type Rejection = ApiError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        let bytes = Bytes::from_request(req, state)
            .await
            .map_err(|rejection| ApiError::bad_request(rejection.body_text()))?;
        Ok(NoteInput::from_json(&bytes)?)
    }
}

impl<S: Send + Sync> FromRequestParts<S> for NoteId {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let Path(raw) = Path::<String>::from_request_parts(parts, state)
            .await
            .map_err(|_| ApiError::NotFound)?;
        NoteId::parse(&raw).ok_or(ApiError::NotFound)
    }
}
