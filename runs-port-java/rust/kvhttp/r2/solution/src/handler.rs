//! Routes requests for the key-value API.

use std::convert::Infallible;
use std::sync::Arc;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::header::{CONTENT_LENGTH, CONTENT_TYPE, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};

use crate::store::KvStore;

/// Largest value accepted by `PUT /kv/<key>`.
pub const MAX_VALUE_BYTES: usize = 1 << 20;

const KV_PREFIX: &str = "/kv/";
const MAX_KEY_LEN: usize = 64;

type Body = Full<Bytes>;

/// Handles one request against the shared store. Never fails: every error maps to a status.
pub async fn handle(
    store: Arc<KvStore>,
    request: Request<Incoming>,
) -> Result<Response<Body>, Infallible> {
    Ok(route(&store, request).await.unwrap_or_else(empty))
}

async fn route(store: &KvStore, request: Request<Incoming>) -> Result<Response<Body>, StatusCode> {
    let path = request.uri().path();
    let method = request.method();

    match path {
        "/health" => {
            require(method, &Method::GET)?;
            Ok(with_type(
                StatusCode::OK,
                "text/plain; charset=utf-8",
                Bytes::from_static(b"ok"),
            ))
        }
        "/kv" => {
            require(method, &Method::GET)?;
            Ok(with_type(
                StatusCode::OK,
                "application/json",
                keys_json(&store.keys()).into(),
            ))
        }
        _ => {
            let key = path.strip_prefix(KV_PREFIX).ok_or(StatusCode::NOT_FOUND)?;
            if !is_valid_key(key) {
                return Err(StatusCode::BAD_REQUEST);
            }
            let key = key.to_owned();
            match *method {
                Method::GET => store
                    .get(&key)
                    .map(|value| with_type(StatusCode::OK, "application/octet-stream", value))
                    .ok_or(StatusCode::NOT_FOUND),
                Method::PUT => {
                    let value = read_body(request).await?;
                    Ok(empty(if store.put(&key, value) {
                        StatusCode::CREATED
                    } else {
                        StatusCode::OK
                    }))
                }
                Method::DELETE => Ok(empty(if store.delete(&key) {
                    StatusCode::NO_CONTENT
                } else {
                    StatusCode::NOT_FOUND
                })),
                _ => Err(StatusCode::METHOD_NOT_ALLOWED),
            }
        }
    }
}

fn require(method: &Method, allowed: &Method) -> Result<(), StatusCode> {
    if method == allowed {
        Ok(())
    } else {
        Err(StatusCode::METHOD_NOT_ALLOWED)
    }
}

/// A key matches `[A-Za-z0-9_-]{1,64}`.
fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Keys are restricted to `[A-Za-z0-9_-]`, so no JSON escaping is required.
fn keys_json(keys: &[String]) -> String {
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
    json
}

async fn read_body(request: Request<Incoming>) -> Result<Bytes, StatusCode> {
    let declared = request
        .headers()
        .get(CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<u64>().ok());
    if declared.is_some_and(|len| len > MAX_VALUE_BYTES as u64) {
        return Err(StatusCode::PAYLOAD_TOO_LARGE);
    }

    match Limited::new(request.into_body(), MAX_VALUE_BYTES)
        .collect()
        .await
    {
        Ok(collected) => Ok(collected.to_bytes()),
        Err(err) if err.is::<LengthLimitError>() => Err(StatusCode::PAYLOAD_TOO_LARGE),
        Err(_) => Err(StatusCode::BAD_REQUEST),
    }
}

fn empty(status: StatusCode) -> Response<Body> {
    let mut response = Response::new(Body::default());
    *response.status_mut() = status;
    response
}

fn with_type(status: StatusCode, content_type: &'static str, body: Bytes) -> Response<Body> {
    let mut response = Response::new(Full::new(body));
    *response.status_mut() = status;
    response
        .headers_mut()
        .insert(CONTENT_TYPE, HeaderValue::from_static(content_type));
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
    }

    #[test]
    fn json_listing() {
        assert_eq!(keys_json(&[]), "[]");
        assert_eq!(keys_json(&["a".into(), "b".into()]), r#"["a","b"]"#);
    }
}
