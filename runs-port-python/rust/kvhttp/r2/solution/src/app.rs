//! Request routing and the HTTP semantics of the key-value API.

use bytes::Bytes;
use http_body_util::Full;
use hyper::header::{ALLOW, CONTENT_TYPE, HeaderValue};
use hyper::{Method, Response, StatusCode};

use crate::store::Store;

/// Largest accepted value (and request body), in bytes.
pub const MAX_VALUE_SIZE: usize = 1024 * 1024;

const MAX_KEY_LEN: usize = 64;
const KV_PREFIX: &str = "/kv/";

pub type Body = Full<Bytes>;

/// Returns `true` if `key` matches `[A-Za-z0-9_-]{1,64}`.
pub fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Builds a response with the given status, body and optional content type.
pub fn response(
    status: StatusCode,
    body: Bytes,
    content_type: Option<&'static str>,
) -> Response<Body> {
    let mut res = Response::new(Full::new(body));
    *res.status_mut() = status;
    if let Some(ct) = content_type {
        res.headers_mut()
            .insert(CONTENT_TYPE, HeaderValue::from_static(ct));
    }
    res
}

pub fn empty(status: StatusCode) -> Response<Body> {
    response(status, Bytes::new(), None)
}

fn method_not_allowed(allow: &'static str) -> Response<Body> {
    let mut res = empty(StatusCode::METHOD_NOT_ALLOWED);
    res.headers_mut()
        .insert(ALLOW, HeaderValue::from_static(allow));
    res
}

/// Dispatches a fully-read request against the store.
pub fn handle(store: &Store, method: &Method, path: &str, body: Bytes) -> Response<Body> {
    match path {
        "/health" => match *method {
            Method::GET => response(
                StatusCode::OK,
                Bytes::from_static(b"ok"),
                Some("text/plain"),
            ),
            _ => method_not_allowed("GET"),
        },
        "/kv" => match *method {
            Method::GET => {
                let json =
                    serde_json::to_vec(&store.keys()).expect("a list of strings always serializes");
                response(StatusCode::OK, json.into(), Some("application/json"))
            }
            _ => method_not_allowed("GET"),
        },
        _ => match path.strip_prefix(KV_PREFIX) {
            Some(key) if is_valid_key(key) => handle_key(store, method, key, body),
            Some(_) => empty(StatusCode::BAD_REQUEST),
            None => empty(StatusCode::NOT_FOUND),
        },
    }
}

fn handle_key(store: &Store, method: &Method, key: &str, body: Bytes) -> Response<Body> {
    match *method {
        Method::GET => match store.get(key) {
            Some(value) => response(StatusCode::OK, value, Some("application/octet-stream")),
            None => empty(StatusCode::NOT_FOUND),
        },
        Method::PUT => {
            let status = if store.put(key, body) {
                StatusCode::CREATED
            } else {
                StatusCode::OK
            };
            empty(status)
        }
        Method::DELETE => {
            let status = if store.delete(key) {
                StatusCode::NO_CONTENT
            } else {
                StatusCode::NOT_FOUND
            };
            empty(status)
        }
        _ => method_not_allowed("GET, PUT, DELETE"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use http_body_util::BodyExt;

    fn call(store: &Store, method: Method, path: &str, body: &'static [u8]) -> (StatusCode, Bytes) {
        let res = handle(store, &method, path, Bytes::from_static(body));
        let status = res.status();
        let body = collect_body(res.into_body());
        (status, body)
    }

    fn collect_body(body: Body) -> Bytes {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(body.collect())
            .unwrap()
            .to_bytes()
    }

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

    #[test]
    fn routes() {
        let s = Store::new();
        assert_eq!(
            call(&s, Method::GET, "/health", b""),
            (StatusCode::OK, Bytes::from_static(b"ok"))
        );
        assert_eq!(
            call(&s, Method::POST, "/health", b"").0,
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(call(&s, Method::GET, "/nope", b"").0, StatusCode::NOT_FOUND);
        assert_eq!(
            call(&s, Method::GET, "/kv/", b"").0,
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            call(&s, Method::GET, "/kv/a/b", b"").0,
            StatusCode::BAD_REQUEST
        );
        assert_eq!(call(&s, Method::PUT, "/kv/b", b"2").0, StatusCode::CREATED);
        assert_eq!(call(&s, Method::PUT, "/kv/a", b"1").0, StatusCode::CREATED);
        assert_eq!(call(&s, Method::PUT, "/kv/a", b"3").0, StatusCode::OK);
        assert_eq!(
            call(&s, Method::GET, "/kv/a", b""),
            (StatusCode::OK, Bytes::from_static(b"3"))
        );
        assert_eq!(
            call(&s, Method::PATCH, "/kv/a", b"").0,
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(
            call(&s, Method::GET, "/kv", b""),
            (StatusCode::OK, Bytes::from_static(br#"["a","b"]"#))
        );
        assert_eq!(
            call(&s, Method::DELETE, "/kv/a", b"").0,
            StatusCode::NO_CONTENT
        );
        assert_eq!(
            call(&s, Method::DELETE, "/kv/a", b"").0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(call(&s, Method::GET, "/kv/a", b"").0, StatusCode::NOT_FOUND);
    }
}
