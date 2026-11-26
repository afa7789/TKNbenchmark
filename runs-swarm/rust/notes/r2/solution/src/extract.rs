//! Request extractors that answer malformed requests with the API's JSON errors.

use axum::body::Bytes;
use axum::extract::rejection::BytesRejection;
use axum::extract::{FromRequest, FromRequestParts, Path, Request};
use axum::http::StatusCode;
use axum::http::request::Parts;
use serde_json::Value;

use crate::error::ApiError;
use crate::model::NoteInput;

/// A request body parsed as JSON. Any syntax error is a 400.
///
/// The `Content-Type` header is not required.
#[derive(Debug)]
pub struct JsonBody(pub Value);

impl<S: Send + Sync> FromRequest<S> for JsonBody {
    type Rejection = ApiError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        let bytes = Bytes::from_request(req, state)
            .await
            .map_err(body_rejection)?;
        serde_json::from_slice(&bytes)
            .map(JsonBody)
            .map_err(|err| ApiError::bad_request(format!("invalid JSON: {err}")))
    }
}

fn body_rejection(rejection: BytesRejection) -> ApiError {
    if rejection.status() == StatusCode::PAYLOAD_TOO_LARGE {
        ApiError::PayloadTooLarge
    } else {
        ApiError::bad_request(rejection.body_text())
    }
}

/// A validated note body (`{title, body?, tags?}`), see [`NoteInput::from_json`].
impl<S: Send + Sync> FromRequest<S> for NoteInput {
    type Rejection = ApiError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        let JsonBody(value) = JsonBody::from_request(req, state).await?;
        Ok(NoteInput::from_json(value)?)
    }
}

/// The `{id}` path parameter of `/notes/{id}`.
///
/// Anything but a positive decimal integer is answered with 404, as no such note can exist.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NoteId(pub i64);

impl NoteId {
    pub fn parse(segment: &str) -> Option<Self> {
        if segment.is_empty() || !segment.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        segment.parse().ok().filter(|&id| id > 0).map(NoteId)
    }
}

impl<S: Send + Sync> FromRequestParts<S> for NoteId {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let Path(segment) = Path::<String>::from_request_parts(parts, state)
            .await
            .map_err(|_| ApiError::NotFound)?;
        NoteId::parse(&segment).ok_or(ApiError::NotFound)
    }
}

#[cfg(test)]
mod tests {
    use super::NoteId;

    #[test]
    fn parses_positive_ids_only() {
        assert_eq!(NoteId::parse("1"), Some(NoteId(1)));
        assert_eq!(NoteId::parse("0042"), Some(NoteId(42)));
        assert_eq!(NoteId::parse("9223372036854775807"), Some(NoteId(i64::MAX)));
        for bad in [
            "",
            "0",
            "-1",
            "+1",
            "abc",
            "1.5",
            " 1",
            "9223372036854775808",
        ] {
            assert_eq!(NoteId::parse(bad), None, "{bad:?}");
        }
    }
}
