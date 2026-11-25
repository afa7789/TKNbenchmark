//! kvhttp: an in-memory HTTP/1.1 key-value server.

use std::collections::BTreeMap;
use std::net::{Ipv4Addr, SocketAddr};
use std::sync::{Arc, PoisonError, RwLock};

use anyhow::{Context, bail};
use axum::Router;
use axum::body::{Body, Bytes};
use axum::extract::{DefaultBodyLimit, Request, State};
use axum::http::{Method, StatusCode};
use axum::response::{IntoResponse, Json, Response};

/// Maximum size of a stored value.
const MAX_VALUE_BYTES: usize = 1 << 20;
/// Maximum length of a key.
const MAX_KEY_LEN: usize = 64;

#[derive(Clone, Default)]
struct AppState {
    store: Arc<RwLock<BTreeMap<String, Bytes>>>,
}

impl AppState {
    fn get(&self, key: &str) -> Option<Bytes> {
        let store = self.store.read().unwrap_or_else(PoisonError::into_inner);
        store.get(key).cloned()
    }

    /// Stores `value`, returning `true` if the key was new.
    fn put(&self, key: &str, value: Bytes) -> bool {
        let mut store = self.store.write().unwrap_or_else(PoisonError::into_inner);
        store.insert(key.to_owned(), value).is_none()
    }

    /// Removes `key`, returning `true` if it existed.
    fn delete(&self, key: &str) -> bool {
        let mut store = self.store.write().unwrap_or_else(PoisonError::into_inner);
        store.remove(key).is_some()
    }

    fn keys(&self) -> Vec<String> {
        let store = self.store.read().unwrap_or_else(PoisonError::into_inner);
        store.keys().cloned().collect()
    }
}

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Routes every request by hand so that 400/404/405 follow the spec exactly.
async fn handle(State(state): State<AppState>, req: Request) -> Response {
    let method = req.method().clone();
    let path = req.uri().path().to_owned();

    match path.as_str() {
        "/health" => match method {
            Method::GET => (StatusCode::OK, "ok").into_response(),
            _ => StatusCode::METHOD_NOT_ALLOWED.into_response(),
        },
        "/kv" => match method {
            Method::GET => Json(state.keys()).into_response(),
            _ => StatusCode::METHOD_NOT_ALLOWED.into_response(),
        },
        _ => match path.strip_prefix("/kv/") {
            Some(key) => handle_key(&state, method, key, req.into_body()).await,
            None => StatusCode::NOT_FOUND.into_response(),
        },
    }
}

async fn handle_key(state: &AppState, method: Method, key: &str, body: Body) -> Response {
    if !matches!(method, Method::GET | Method::PUT | Method::DELETE) {
        return StatusCode::METHOD_NOT_ALLOWED.into_response();
    }
    if !is_valid_key(key) {
        return StatusCode::BAD_REQUEST.into_response();
    }
    match method {
        Method::GET => match state.get(key) {
            Some(value) => (StatusCode::OK, value).into_response(),
            None => StatusCode::NOT_FOUND.into_response(),
        },
        Method::PUT => match axum::body::to_bytes(body, MAX_VALUE_BYTES).await {
            Ok(value) => {
                if state.put(key, value) {
                    StatusCode::CREATED.into_response()
                } else {
                    StatusCode::OK.into_response()
                }
            }
            Err(_) => StatusCode::PAYLOAD_TOO_LARGE.into_response(),
        },
        _ => {
            if state.delete(key) {
                StatusCode::NO_CONTENT.into_response()
            } else {
                StatusCode::NOT_FOUND.into_response()
            }
        }
    }
}

fn app() -> Router {
    Router::new()
        .fallback(handle)
        .layer(DefaultBodyLimit::max(MAX_VALUE_BYTES))
        .with_state(AppState::default())
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let (Some(port), None) = (args.next(), args.next()) else {
        bail!("usage: app <port>");
    };
    let port: u16 = port.parse().with_context(|| format!("invalid port {port:?}"))?;

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("failed to bind {addr}"))?;
    axum::serve(listener, app()).await.context("server error")
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
        assert!(!is_valid_key("a%20b"));
    }
}
