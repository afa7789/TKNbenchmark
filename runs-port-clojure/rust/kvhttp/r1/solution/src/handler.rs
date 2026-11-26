//! HTTP routing for the kvhttp API.

use std::sync::Arc;

use axum::Router;
use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, State};
use axum::http::{HeaderValue, Method, StatusCode, Uri, header};
use axum::response::{IntoResponse, Response};

use crate::store::Store;

/// Largest accepted request body: 1 MiB values plus generous headroom.
const MAX_BODY: usize = 8 * 1024 * 1024;

const ALLOW_COLLECTION: &str = "GET";
const ALLOW_ITEM: &str = "GET, PUT, DELETE";

/// Builds the application router backed by `store`.
pub fn router(store: Arc<Store>) -> Router {
    Router::new()
        .fallback(dispatch)
        .layer(DefaultBodyLimit::max(MAX_BODY))
        .with_state(store)
}

/// Returns `true` if `key` matches `[A-Za-z0-9_-]{1,64}`.
fn is_valid_key(key: &str) -> bool {
    (1..=64).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

async fn dispatch(
    State(store): State<Arc<Store>>,
    method: Method,
    uri: Uri,
    body: Bytes,
) -> Response {
    match uri.path() {
        "/health" => health(&method),
        "/kv" => list_keys(&store, &method),
        path => match path.strip_prefix("/kv/") {
            Some(key) => item(&store, &method, key, body),
            None => StatusCode::NOT_FOUND.into_response(),
        },
    }
}

fn method_not_allowed(allowed: &'static str) -> Response {
    (
        StatusCode::METHOD_NOT_ALLOWED,
        [(header::ALLOW, HeaderValue::from_static(allowed))],
    )
        .into_response()
}

fn health(method: &Method) -> Response {
    if method == Method::GET {
        (StatusCode::OK, "ok").into_response()
    } else {
        method_not_allowed(ALLOW_COLLECTION)
    }
}

fn list_keys(store: &Store, method: &Method) -> Response {
    if method != Method::GET {
        return method_not_allowed(ALLOW_COLLECTION);
    }
    let json = serde_json::to_vec(&store.keys()).expect("a list of strings always serializes");
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, HeaderValue::from_static("application/json"))],
        json,
    )
        .into_response()
}

fn item(store: &Store, method: &Method, key: &str, body: Bytes) -> Response {
    if !is_valid_key(key) {
        return StatusCode::BAD_REQUEST.into_response();
    }
    match *method {
        Method::GET => match store.get(key) {
            Some(value) => (
                StatusCode::OK,
                [(
                    header::CONTENT_TYPE,
                    HeaderValue::from_static("application/octet-stream"),
                )],
                value,
            )
                .into_response(),
            None => StatusCode::NOT_FOUND.into_response(),
        },
        Method::PUT => {
            if store.put(key, body) {
                StatusCode::CREATED.into_response()
            } else {
                StatusCode::OK.into_response()
            }
        }
        Method::DELETE => {
            if store.delete(key) {
                StatusCode::NO_CONTENT.into_response()
            } else {
                StatusCode::NOT_FOUND.into_response()
            }
        }
        _ => method_not_allowed(ALLOW_ITEM),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_validation() {
        assert!(is_valid_key("a"));
        assert!(is_valid_key("A-z_09"));
        assert!(is_valid_key(&"a".repeat(64)));
        assert!(!is_valid_key(""));
        assert!(!is_valid_key(&"a".repeat(65)));
        assert!(!is_valid_key("a/b"));
        assert!(!is_valid_key("bad.key"));
        assert!(!is_valid_key("é"));
    }
}
