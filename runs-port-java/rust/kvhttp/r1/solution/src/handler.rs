//! Routes and serves all requests for the key-value HTTP API.

use std::sync::Arc;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::header::{self, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};

use crate::store::KvStore;

/// Largest accepted value, in bytes.
pub const MAX_VALUE_BYTES: usize = 1 << 20;

const KV_PREFIX: &str = "/kv/";
const MAX_KEY_LEN: usize = 64;

/// Returns whether `key` matches `[A-Za-z0-9_-]{1,64}`.
fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Serves one request. Never fails: every error is mapped to an HTTP status.
pub async fn handle(
    store: Arc<KvStore>,
    request: Request<Incoming>,
) -> Result<Response<Full<Bytes>>, std::convert::Infallible> {
    Ok(route(&store, request).await)
}

async fn route(store: &KvStore, request: Request<Incoming>) -> Response<Full<Bytes>> {
    let path = request.uri().path();

    match path {
        "/health" => match *request.method() {
            Method::GET => text(StatusCode::OK, "ok"),
            _ => status(StatusCode::METHOD_NOT_ALLOWED),
        },
        "/kv" => match *request.method() {
            Method::GET => list_keys(store),
            _ => status(StatusCode::METHOD_NOT_ALLOWED),
        },
        _ => match path.strip_prefix(KV_PREFIX) {
            Some(key) if !is_valid_key(key) => status(StatusCode::BAD_REQUEST),
            Some(key) => {
                let key = key.to_owned();
                match request.method().clone() {
                    Method::GET => match store.get(&key) {
                        Some(value) => with_body(StatusCode::OK, "application/octet-stream", value),
                        None => status(StatusCode::NOT_FOUND),
                    },
                    Method::PUT => match read_body(request).await {
                        Ok(value) => status(if store.put(&key, value) {
                            StatusCode::CREATED
                        } else {
                            StatusCode::OK
                        }),
                        Err(code) => status(code),
                    },
                    Method::DELETE if store.delete(&key) => status(StatusCode::NO_CONTENT),
                    Method::DELETE => status(StatusCode::NOT_FOUND),
                    _ => status(StatusCode::METHOD_NOT_ALLOWED),
                }
            }
            None => status(StatusCode::NOT_FOUND),
        },
    }
}

/// Reads the request body, enforcing [`MAX_VALUE_BYTES`].
async fn read_body(request: Request<Incoming>) -> Result<Bytes, StatusCode> {
    let declared = request
        .headers()
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<u64>().ok());
    if declared.is_some_and(|len| len > MAX_VALUE_BYTES as u64) {
        return Err(StatusCode::PAYLOAD_TOO_LARGE);
    }

    match Limited::new(request.into_body(), MAX_VALUE_BYTES).collect().await {
        Ok(collected) => Ok(collected.to_bytes()),
        Err(e) if e.is::<LengthLimitError>() => Err(StatusCode::PAYLOAD_TOO_LARGE),
        Err(_) => Err(StatusCode::BAD_REQUEST),
    }
}

fn list_keys(store: &KvStore) -> Response<Full<Bytes>> {
    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
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
    with_body(StatusCode::OK, "application/json", Bytes::from(json))
}

fn status(code: StatusCode) -> Response<Full<Bytes>> {
    let mut response = Response::new(Full::default());
    *response.status_mut() = code;
    response
}

fn text(code: StatusCode, body: &'static str) -> Response<Full<Bytes>> {
    with_body(code, "text/plain; charset=utf-8", Bytes::from_static(body.as_bytes()))
}

fn with_body(code: StatusCode, content_type: &'static str, body: Bytes) -> Response<Full<Bytes>> {
    let mut response = Response::new(Full::new(body));
    *response.status_mut() = code;
    response
        .headers_mut()
        .insert(header::CONTENT_TYPE, HeaderValue::from_static(content_type));
    response
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert!(!is_valid_key("é"));
    }
}
