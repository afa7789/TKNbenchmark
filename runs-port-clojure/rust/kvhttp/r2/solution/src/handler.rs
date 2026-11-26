//! HTTP routing for the kvhttp API.

use std::sync::Arc;

use axum::body::{self, Body, Bytes};
use axum::extract::{Request, State};
use axum::http::{Method, StatusCode, header};
use axum::response::{IntoResponse, Response};

use crate::store::{PutOutcome, Store};

/// Largest value accepted by `PUT /kv/<key>`.
pub const MAX_VALUE_BYTES: usize = 1024 * 1024;

const MAX_KEY_LEN: usize = 64;

/// Builds the application router backed by `store`.
pub fn router(store: Arc<Store>) -> axum::Router {
    axum::Router::new().fallback(dispatch).with_state(store)
}

async fn dispatch(State(store): State<Arc<Store>>, req: Request) -> Response {
    let (parts, body) = req.into_parts();
    let path = parts.uri.path();
    let method = parts.method;

    match path {
        "/health" => health(&method),
        "/kv" => list(&store, &method),
        _ => match path.strip_prefix("/kv/") {
            Some(key) => item(&store, &method, key, body).await,
            None => StatusCode::NOT_FOUND.into_response(),
        },
    }
}

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn health(method: &Method) -> Response {
    if method == Method::GET {
        (StatusCode::OK, "ok").into_response()
    } else {
        StatusCode::METHOD_NOT_ALLOWED.into_response()
    }
}

fn list(store: &Store, method: &Method) -> Response {
    if method != Method::GET {
        return StatusCode::METHOD_NOT_ALLOWED.into_response();
    }
    // Keys are restricted to `[A-Za-z0-9_-]`, so they never need escaping.
    let keys = store.keys();
    let mut json = String::with_capacity(2 + keys.iter().map(|k| k.len() + 3).sum::<usize>());
    json.push('[');
    for (i, key) in keys.iter().enumerate() {
        if i > 0 {
            json.push(',');
        }
        json.push('"');
        json.push_str(key);
        json.push('"');
    }
    json.push(']');
    ([(header::CONTENT_TYPE, "application/json")], json).into_response()
}

async fn item(store: &Store, method: &Method, key: &str, body: Body) -> Response {
    if !is_valid_key(key) {
        return StatusCode::BAD_REQUEST.into_response();
    }
    match *method {
        Method::GET => match store.get(key) {
            Some(value) => (
                [(header::CONTENT_TYPE, "application/octet-stream")],
                value,
            )
                .into_response(),
            None => StatusCode::NOT_FOUND.into_response(),
        },
        Method::PUT => {
            let value: Bytes = match body::to_bytes(body, MAX_VALUE_BYTES).await {
                Ok(value) => value,
                Err(_) => return StatusCode::PAYLOAD_TOO_LARGE.into_response(),
            };
            match store.put(key, value) {
                PutOutcome::Created => StatusCode::CREATED,
                PutOutcome::Replaced => StatusCode::OK,
            }
            .into_response()
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
        assert!(!is_valid_key("%41"));
    }
}
