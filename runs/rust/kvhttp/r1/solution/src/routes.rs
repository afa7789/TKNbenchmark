//! Request routing and the in-memory key-value store.

use std::collections::BTreeMap;
use std::convert::Infallible;
use std::sync::{Arc, RwLock};

use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper::body::Incoming;
use hyper::header::{ALLOW, CONTENT_TYPE, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};

/// Maximum size of a stored value.
pub const MAX_VALUE_LEN: usize = 1024 * 1024;
const MAX_KEY_LEN: usize = 64;

type Body = Full<Bytes>;

/// Thread-safe in-memory store. A `BTreeMap` keeps keys sorted for listing.
#[derive(Default)]
pub struct Store {
    map: RwLock<BTreeMap<String, Bytes>>,
}

impl Store {
    /// Inserts `value`, returning `true` if the key was not present before.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        self.write().insert(key.to_owned(), value).is_none()
    }

    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.read().get(key).cloned()
    }

    /// Removes the key, returning `true` if it existed.
    pub fn delete(&self, key: &str) -> bool {
        self.write().remove(key).is_some()
    }

    pub fn keys(&self) -> Vec<String> {
        self.read().keys().cloned().collect()
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, BTreeMap<String, Bytes>> {
        // A panic while holding the lock cannot leave the map inconsistent.
        self.map.read().unwrap_or_else(|e| e.into_inner())
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, BTreeMap<String, Bytes>> {
        self.map.write().unwrap_or_else(|e| e.into_inner())
    }
}

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// The resource a request path refers to.
#[derive(Debug, PartialEq, Eq)]
enum Route<'a> {
    Health,
    List,
    Key(&'a str),
    InvalidKey,
    NotFound,
}

fn route(path: &str) -> Route<'_> {
    match path {
        "/health" => Route::Health,
        "/kv" => Route::List,
        _ => match path.strip_prefix("/kv/") {
            Some(key) if is_valid_key(key) => Route::Key(key),
            Some(_) => Route::InvalidKey,
            None => Route::NotFound,
        },
    }
}

fn empty(status: StatusCode) -> Response<Body> {
    let mut res = Response::new(Body::default());
    *res.status_mut() = status;
    res
}

fn with_body(status: StatusCode, content_type: &'static str, body: impl Into<Bytes>) -> Response<Body> {
    let mut res = Response::new(Full::new(body.into()));
    *res.status_mut() = status;
    res.headers_mut()
        .insert(CONTENT_TYPE, HeaderValue::from_static(content_type));
    res
}

fn method_not_allowed(allow: &'static str) -> Response<Body> {
    let mut res = empty(StatusCode::METHOD_NOT_ALLOWED);
    res.headers_mut().insert(ALLOW, HeaderValue::from_static(allow));
    res
}

fn json_string_array(items: &[String]) -> String {
    // Keys are restricted to `[A-Za-z0-9_-]`, so no JSON escaping is needed.
    let mut out = String::with_capacity(2 + items.iter().map(|s| s.len() + 3).sum::<usize>());
    out.push('[');
    for (i, item) in items.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('"');
        out.push_str(item);
        out.push('"');
    }
    out.push(']');
    out
}

/// Handles a single HTTP request against `store`.
pub async fn handle(store: Arc<Store>, req: Request<Incoming>) -> Result<Response<Body>, Infallible> {
    let (parts, body) = req.into_parts();
    let res = match (route(parts.uri.path()), &parts.method) {
        (Route::Health, &Method::GET) => with_body(StatusCode::OK, "text/plain", "ok"),
        (Route::Health, _) => method_not_allowed("GET"),

        (Route::List, &Method::GET) => with_body(
            StatusCode::OK,
            "application/json",
            json_string_array(&store.keys()),
        ),
        (Route::List, _) => method_not_allowed("GET"),

        (Route::Key(key), &Method::GET) => match store.get(key) {
            Some(value) => with_body(StatusCode::OK, "application/octet-stream", value),
            None => empty(StatusCode::NOT_FOUND),
        },
        (Route::Key(key), &Method::PUT) => {
            match Limited::new(body, MAX_VALUE_LEN).collect().await {
                Ok(collected) => {
                    if store.put(key, collected.to_bytes()) {
                        empty(StatusCode::CREATED)
                    } else {
                        empty(StatusCode::OK)
                    }
                }
                Err(e) if e.is::<http_body_util::LengthLimitError>() => {
                    empty(StatusCode::PAYLOAD_TOO_LARGE)
                }
                Err(_) => empty(StatusCode::BAD_REQUEST),
            }
        }
        (Route::Key(key), &Method::DELETE) => {
            if store.delete(key) {
                empty(StatusCode::NO_CONTENT)
            } else {
                empty(StatusCode::NOT_FOUND)
            }
        }
        (Route::Key(_), _) => method_not_allowed("GET, PUT, DELETE"),

        (Route::InvalidKey, _) => empty(StatusCode::BAD_REQUEST),
        (Route::NotFound, _) => empty(StatusCode::NOT_FOUND),
    };
    Ok(res)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn routes_paths() {
        assert_eq!(route("/health"), Route::Health);
        assert_eq!(route("/kv"), Route::List);
        assert_eq!(route("/kv/a-B_9"), Route::Key("a-B_9"));
        assert_eq!(route("/kv/"), Route::InvalidKey);
        assert_eq!(route("/kv/a/b"), Route::InvalidKey);
        assert_eq!(route("/kv/bad.key"), Route::InvalidKey);
        assert_eq!(route(&format!("/kv/{}", "x".repeat(64))), Route::Key(&"x".repeat(64)));
        assert_eq!(route(&format!("/kv/{}", "x".repeat(65))), Route::InvalidKey);
        assert_eq!(route("/kvx"), Route::NotFound);
        assert_eq!(route("/"), Route::NotFound);
        assert_eq!(route("/health/"), Route::NotFound);
    }

    #[test]
    fn store_semantics() {
        let store = Store::default();
        assert!(store.put("b", Bytes::from_static(b"1")));
        assert!(!store.put("b", Bytes::from_static(b"2")));
        assert!(store.put("a", Bytes::new()));
        assert_eq!(store.get("b").as_deref(), Some(&b"2"[..]));
        assert_eq!(json_string_array(&store.keys()), r#"["a","b"]"#);
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(json_string_array(&store.keys()), r#"["b"]"#);
        assert_eq!(json_string_array(&[]), "[]");
    }
}
