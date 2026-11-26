//! Request routing and handlers for the kvhttp API.

use std::sync::Arc;

use axum::body::{Body, Bytes};
use axum::extract::{Request, State};
use axum::http::{Method, StatusCode, header};
use axum::response::{IntoResponse, Response};

use crate::store::{PutOutcome, Store};

/// Bodies are capped well above the 1 MiB value limit so oversized values are not cut mid-read.
pub const MAX_BODY_BYTES: usize = 8 * 1024 * 1024;

const KV_PREFIX: &str = "/kv/";

/// Returns true if `key` matches `[A-Za-z0-9_-]{1,64}`.
fn is_valid_key(key: &str) -> bool {
    (1..=64).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Entry point for every request: dispatches on the path, then on the method.
pub async fn handle(State(store): State<Arc<Store>>, req: Request) -> Response {
    let path = req.uri().path();
    if path == "/health" {
        return health(req.method());
    }
    if path == "/kv" {
        return list_keys(&store, req.method());
    }
    let Some(key) = path.strip_prefix(KV_PREFIX) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if !is_valid_key(key) {
        return StatusCode::BAD_REQUEST.into_response();
    }
    let key = key.to_owned();
    entry(&store, &key, req).await
}

fn health(method: &Method) -> Response {
    match *method {
        Method::GET => "ok".into_response(),
        _ => StatusCode::METHOD_NOT_ALLOWED.into_response(),
    }
}

fn list_keys(store: &Store, method: &Method) -> Response {
    if *method != Method::GET {
        return StatusCode::METHOD_NOT_ALLOWED.into_response();
    }
    let body = serde_json::to_vec(&store.keys()).expect("serializing strings cannot fail");
    ([(header::CONTENT_TYPE, "application/json")], body).into_response()
}

async fn entry(store: &Store, key: &str, req: Request) -> Response {
    match req.method().clone() {
        Method::GET => match store.get(key) {
            Some(value) => (
                [(header::CONTENT_TYPE, "application/octet-stream")],
                Body::from(value),
            )
                .into_response(),
            None => StatusCode::NOT_FOUND.into_response(),
        },
        Method::PUT => {
            let value = match read_body(req).await {
                Ok(value) => value,
                Err(response) => return response,
            };
            match store.put(key, value) {
                PutOutcome::Created => StatusCode::CREATED.into_response(),
                PutOutcome::Replaced => StatusCode::OK.into_response(),
            }
        }
        Method::DELETE => {
            if store.delete(key) {
                StatusCode::NO_CONTENT.into_response()
            } else {
                StatusCode::NOT_FOUND.into_response()
            }
        }
        _ => StatusCode::METHOD_NOT_ALLOWED.into_response(),
    }
}

async fn read_body(req: Request) -> Result<Bytes, Response> {
    axum::body::to_bytes(req.into_body(), MAX_BODY_BYTES)
        .await
        .map_err(|_| StatusCode::PAYLOAD_TOO_LARGE.into_response())
}

#[cfg(test)]
mod tests {
    use super::is_valid_key;

    #[test]
    fn key_validation() {
        assert!(is_valid_key("a"));
        assert!(is_valid_key("A-z_09"));
        assert!(is_valid_key(&"k".repeat(64)));
        assert!(!is_valid_key(""));
        assert!(!is_valid_key(&"k".repeat(65)));
        assert!(!is_valid_key("a/b"));
        assert!(!is_valid_key("bad.key"));
        assert!(!is_valid_key("é"));
    }
}
