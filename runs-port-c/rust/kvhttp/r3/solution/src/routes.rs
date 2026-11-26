//! Maps HTTP requests onto key-value store operations.

use bytes::Bytes;
use http_body_util::Full;
use hyper::header::{CONTENT_TYPE, HeaderValue};
use hyper::{Method, Response, StatusCode};

use crate::store::Store;

/// Longest accepted key, in bytes.
pub const MAX_KEY_LEN: usize = 64;
/// Largest accepted value (and request body), in bytes.
pub const MAX_VALUE_LEN: usize = 1024 * 1024;

const KV_PREFIX: &str = "/kv/";

/// The resource a request path refers to.
#[derive(Debug, PartialEq, Eq)]
enum Resource<'a> {
    Health,
    Keys,
    Item(&'a str),
    InvalidKey,
    Unknown,
}

impl<'a> Resource<'a> {
    fn from_path(path: &'a str) -> Self {
        match path {
            "/health" => Self::Health,
            "/kv" => Self::Keys,
            _ => match path.strip_prefix(KV_PREFIX) {
                Some(key) if is_valid_key(key) => Self::Item(key),
                Some(_) => Self::InvalidKey,
                None => Self::Unknown,
            },
        }
    }
}

/// A key matches `[A-Za-z0-9_-]{1,64}`.
pub fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Handles one fully received request.
pub fn handle(store: &Store, method: &Method, path: &str, body: Bytes) -> Response<Full<Bytes>> {
    match Resource::from_path(path) {
        Resource::Health if method == Method::GET => respond(
            StatusCode::OK,
            Some("text/plain"),
            Bytes::from_static(b"ok"),
        ),
        Resource::Keys if method == Method::GET => list_keys(store),
        Resource::Item(key) => handle_item(store, method, key, body),
        Resource::Health | Resource::Keys => status(StatusCode::METHOD_NOT_ALLOWED),
        Resource::InvalidKey => status(StatusCode::BAD_REQUEST),
        Resource::Unknown => status(StatusCode::NOT_FOUND),
    }
}

fn handle_item(store: &Store, method: &Method, key: &str, body: Bytes) -> Response<Full<Bytes>> {
    match *method {
        Method::GET => match store.get(key) {
            Some(value) => respond(StatusCode::OK, Some("application/octet-stream"), value),
            None => status(StatusCode::NOT_FOUND),
        },
        Method::PUT => {
            if store.put(key, body) {
                status(StatusCode::CREATED)
            } else {
                status(StatusCode::OK)
            }
        }
        Method::DELETE => {
            if store.delete(key) {
                status(StatusCode::NO_CONTENT)
            } else {
                status(StatusCode::NOT_FOUND)
            }
        }
        _ => status(StatusCode::METHOD_NOT_ALLOWED),
    }
}

/// Serializes all keys as a sorted JSON array. Valid keys never need escaping.
fn list_keys(store: &Store) -> Response<Full<Bytes>> {
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
    respond(StatusCode::OK, Some("application/json"), Bytes::from(json))
}

/// A response with an empty body.
pub fn status(code: StatusCode) -> Response<Full<Bytes>> {
    respond(code, None, Bytes::new())
}

fn respond(
    code: StatusCode,
    content_type: Option<&'static str>,
    body: Bytes,
) -> Response<Full<Bytes>> {
    let mut response = Response::new(Full::new(body));
    *response.status_mut() = code;
    if let Some(content_type) = content_type {
        response
            .headers_mut()
            .insert(CONTENT_TYPE, HeaderValue::from_static(content_type));
    }
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use http_body_util::BodyExt;

    fn call(store: &Store, method: Method, path: &str, body: &'static [u8]) -> (StatusCode, Bytes) {
        let response = handle(store, &method, path, Bytes::from_static(body));
        let code = response.status();
        let body = collect_body(response.into_body());
        (code, body)
    }

    fn collect_body(body: Full<Bytes>) -> Bytes {
        let rt = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        rt.block_on(body.collect()).unwrap().to_bytes()
    }

    #[test]
    fn key_validation() {
        assert!(is_valid_key("a"));
        assert!(is_valid_key("A-z_09"));
        assert!(is_valid_key(&"k".repeat(MAX_KEY_LEN)));
        assert!(!is_valid_key(""));
        assert!(!is_valid_key(&"k".repeat(MAX_KEY_LEN + 1)));
        assert!(!is_valid_key("a/b"));
        assert!(!is_valid_key("a.b"));
        assert!(!is_valid_key("a%20"));
        assert!(!is_valid_key("é"));
    }

    #[test]
    fn routing() {
        assert_eq!(Resource::from_path("/health"), Resource::Health);
        assert_eq!(Resource::from_path("/kv"), Resource::Keys);
        assert_eq!(Resource::from_path("/kv/x"), Resource::Item("x"));
        assert_eq!(Resource::from_path("/kv/"), Resource::InvalidKey);
        assert_eq!(Resource::from_path("/kv/a/b"), Resource::InvalidKey);
        assert_eq!(Resource::from_path("/kvx"), Resource::Unknown);
        assert_eq!(Resource::from_path("/health/"), Resource::Unknown);
        assert_eq!(Resource::from_path("/"), Resource::Unknown);
    }

    #[test]
    fn crud_and_errors() {
        let store = Store::new();
        assert_eq!(call(&store, Method::GET, "/health", b"").1, "ok");
        assert_eq!(
            call(&store, Method::POST, "/health", b"").0,
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(
            call(&store, Method::PUT, "/kv/b", b"2").0,
            StatusCode::CREATED
        );
        assert_eq!(
            call(&store, Method::PUT, "/kv/a", b"1").0,
            StatusCode::CREATED
        );
        assert_eq!(call(&store, Method::PUT, "/kv/a", b"one").0, StatusCode::OK);
        assert_eq!(
            call(&store, Method::GET, "/kv/a", b""),
            (StatusCode::OK, Bytes::from_static(b"one"))
        );
        assert_eq!(call(&store, Method::GET, "/kv", b"").1, r#"["a","b"]"#);
        assert_eq!(
            call(&store, Method::DELETE, "/kv/a", b"").0,
            StatusCode::NO_CONTENT
        );
        assert_eq!(
            call(&store, Method::DELETE, "/kv/a", b"").0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            call(&store, Method::GET, "/kv/a", b"").0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            call(&store, Method::PATCH, "/kv/a", b"").0,
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(
            call(&store, Method::PUT, "/kv", b"").0,
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(
            call(&store, Method::PATCH, "/kv/a.b", b"").0,
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            call(&store, Method::GET, "/nope", b"").0,
            StatusCode::NOT_FOUND
        );
    }
}
