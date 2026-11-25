//! In-memory HTTP key-value store.

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::sync::{Arc, PoisonError, RwLock};

use axum::{
    Router,
    body::Bytes,
    extract::{DefaultBodyLimit, State},
    http::{Method, StatusCode, Uri, header},
    response::{IntoResponse, Response},
    routing::{any, get},
};

/// Maximum size of a stored value.
pub const MAX_VALUE_LEN: usize = 1024 * 1024;

const KV_PREFIX: &str = "/kv/";

#[derive(Default)]
struct Store {
    map: RwLock<BTreeMap<String, Bytes>>,
}

impl Store {
    /// Inserts `value`, returning `true` if the key was new.
    fn put(&self, key: String, value: Bytes) -> bool {
        self.map
            .write()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(key, value)
            .is_none()
    }

    fn get(&self, key: &str) -> Option<Bytes> {
        self.map
            .read()
            .unwrap_or_else(PoisonError::into_inner)
            .get(key)
            .cloned()
    }

    fn delete(&self, key: &str) -> bool {
        self.map
            .write()
            .unwrap_or_else(PoisonError::into_inner)
            .remove(key)
            .is_some()
    }

    /// Keys in ascending order, serialized as a JSON array.
    fn keys_json(&self) -> String {
        let map = self.map.read().unwrap_or_else(PoisonError::into_inner);
        let mut out = String::with_capacity(2 + map.keys().map(|k| k.len() + 3).sum::<usize>());
        out.push('[');
        for (i, key) in map.keys().enumerate() {
            if i > 0 {
                out.push(',');
            }
            // Valid keys contain only [A-Za-z0-9_-], so no JSON escaping is needed.
            let _ = write!(out, "\"{key}\"");
        }
        out.push(']');
        out
    }
}

type SharedStore = Arc<Store>;

/// Returns `true` if `key` matches `[A-Za-z0-9_-]{1,64}`.
#[must_use]
pub fn is_valid_key(key: &str) -> bool {
    (1..=64).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Builds the application router with a fresh, empty store.
pub fn router() -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/kv", get(list_keys))
        .route("/kv/", any(item))
        .route("/kv/{*rest}", any(item))
        .fallback(not_found)
        .layer(DefaultBodyLimit::max(MAX_VALUE_LEN))
        .with_state(SharedStore::default())
}

async fn health() -> &'static str {
    "ok"
}

async fn not_found() -> StatusCode {
    StatusCode::NOT_FOUND
}

async fn list_keys(State(store): State<SharedStore>) -> Response {
    (
        [(header::CONTENT_TYPE, "application/json")],
        store.keys_json(),
    )
        .into_response()
}

async fn item(State(store): State<SharedStore>, method: Method, uri: Uri, body: Bytes) -> Response {
    // Use the raw (undecoded) path so that e.g. `%2F` is not silently accepted.
    let key = uri.path().strip_prefix(KV_PREFIX).unwrap_or_default();
    if !is_valid_key(key) {
        return StatusCode::BAD_REQUEST.into_response();
    }

    match method {
        Method::GET | Method::HEAD => match store.get(key) {
            Some(value) => value.into_response(),
            None => StatusCode::NOT_FOUND.into_response(),
        },
        Method::PUT => {
            if store.put(key.to_owned(), body) {
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
        _ => (
            StatusCode::METHOD_NOT_ALLOWED,
            [(header::ALLOW, "GET,HEAD,PUT,DELETE")],
        )
            .into_response(),
    }
}

#[cfg(test)]
mod tests {
    use super::is_valid_key;

    #[test]
    fn key_validation() {
        assert!(is_valid_key("a"));
        assert!(is_valid_key("Az09_-"));
        assert!(is_valid_key(&"k".repeat(64)));
        assert!(!is_valid_key(""));
        assert!(!is_valid_key(&"k".repeat(65)));
        assert!(!is_valid_key("a/b"));
        assert!(!is_valid_key("bad.key"));
        assert!(!is_valid_key("é"));
    }
}
