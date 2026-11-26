//! The error type returned by handlers, rendered as `{"error": "<message>"}`.

use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::json;

use crate::note::InvalidNote;
use crate::store::StoreError;

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("{0}")]
    BadRequest(String),
    #[error("not found")]
    NotFound,
    #[error("method not allowed")]
    MethodNotAllowed,
    #[error(transparent)]
    Store(#[from] StoreError),
}

impl ApiError {
    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::BadRequest(message.into())
    }

    pub fn status(&self) -> StatusCode {
        match self {
            Self::BadRequest(_) => StatusCode::BAD_REQUEST,
            Self::NotFound => StatusCode::NOT_FOUND,
            Self::MethodNotAllowed => StatusCode::METHOD_NOT_ALLOWED,
            Self::Store(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

impl From<InvalidNote> for ApiError {
    fn from(err: InvalidNote) -> Self {
        Self::BadRequest(err.to_string())
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let message = match &self {
            Self::Store(err) => {
                // Details stay in the log; clients get a generic message.
                tracing::error!(error = %err, "request failed");
                "internal server error".to_owned()
            }
            other => other.to_string(),
        };
        (self.status(), Json(json!({ "error": message }))).into_response()
    }
}

pub type ApiResult<T> = Result<T, ApiError>;
