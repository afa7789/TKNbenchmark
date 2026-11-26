//! HTTP routing and request handling.

use std::convert::Infallible;
use std::sync::Arc;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::{Body, Incoming};
use hyper::header::{ALLOW, CONNECTION, CONTENT_LENGTH, CONTENT_TYPE, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};

use crate::store::KvStore;

/// Largest accepted value, in bytes.
pub const MAX_VALUE_BYTES: usize = 1024 * 1024;
const KV_PREFIX: &str = "/kv/";
const MAX_KEY_LEN: usize = 64;

/// Returns whether `key` matches `[A-Za-z0-9_-]{1,64}`.
fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn send(
    status: StatusCode,
    body: impl Into<Bytes>,
    content_type: Option<&'static str>,
) -> Response<Full<Bytes>> {
    let body = body.into();
    let mut res = Response::new(Full::new(body.clone()));
    *res.status_mut() = status;
    let headers = res.headers_mut();
    headers.insert(CONTENT_LENGTH, HeaderValue::from(body.len()));
    if let Some(ct) = content_type {
        headers.insert(CONTENT_TYPE, HeaderValue::from_static(ct));
    }
    res
}

fn empty(status: StatusCode) -> Response<Full<Bytes>> {
    send(status, Bytes::new(), None)
}

fn method_not_allowed(allowed: &'static str) -> Response<Full<Bytes>> {
    let mut res = empty(StatusCode::METHOD_NOT_ALLOWED);
    res.headers_mut()
        .insert(ALLOW, HeaderValue::from_static(allowed));
    res
}

/// An error response that also closes the connection, since the request body
/// may not have been fully consumed.
fn fatal(status: StatusCode) -> Response<Full<Bytes>> {
    let mut res = empty(status);
    res.headers_mut()
        .insert(CONNECTION, HeaderValue::from_static("close"));
    res
}

/// Reads the request body, rejecting it with `413` if it exceeds `limit` bytes.
async fn read_body(body: Incoming, limit: usize) -> Result<Bytes, StatusCode> {
    if body.size_hint().lower() > limit as u64 {
        return Err(StatusCode::PAYLOAD_TOO_LARGE);
    }
    match Limited::new(body, limit).collect().await {
        Ok(collected) => Ok(collected.to_bytes()),
        Err(err) if err.is::<LengthLimitError>() => Err(StatusCode::PAYLOAD_TOO_LARGE),
        Err(_) => Err(StatusCode::BAD_REQUEST),
    }
}

/// Handles a single request against `store`.
pub async fn handle(
    store: Arc<KvStore>,
    req: Request<Incoming>,
) -> Result<Response<Full<Bytes>>, Infallible> {
    let (parts, body) = req.into_parts();
    let method = parts.method;
    let path = parts.uri.path();

    let res = match path {
        "/health" => match method {
            Method::GET => send(StatusCode::OK, "ok", Some("text/plain; charset=utf-8")),
            _ => method_not_allowed("GET"),
        },
        "/kv" => match method {
            Method::GET => send(
                StatusCode::OK,
                keys_json(&store.keys()),
                Some("application/json"),
            ),
            _ => method_not_allowed("GET"),
        },
        _ => match path.strip_prefix(KV_PREFIX) {
            Some(key) if !is_valid_key(key) => empty(StatusCode::BAD_REQUEST),
            Some(key) => match method {
                Method::GET => match store.get(key) {
                    Some(value) => send(StatusCode::OK, value, Some("application/octet-stream")),
                    None => empty(StatusCode::NOT_FOUND),
                },
                Method::PUT => match read_body(body, MAX_VALUE_BYTES).await {
                    Ok(value) => {
                        let created = store.set(key, value);
                        empty(if created {
                            StatusCode::CREATED
                        } else {
                            StatusCode::OK
                        })
                    }
                    Err(status) => fatal(status),
                },
                Method::DELETE if store.delete(key) => empty(StatusCode::NO_CONTENT),
                Method::DELETE => empty(StatusCode::NOT_FOUND),
                _ => method_not_allowed("GET, PUT, DELETE"),
            },
            None => empty(StatusCode::NOT_FOUND),
        },
    };
    Ok(res)
}

/// Serializes keys as a JSON array. Valid keys never need escaping.
fn keys_json(keys: &[String]) -> String {
    let mut out = String::with_capacity(2 + keys.iter().map(|k| k.len() + 3).sum::<usize>());
    out.push('[');
    for (i, key) in keys.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('"');
        out.push_str(key);
        out.push('"');
    }
    out.push(']');
    out
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
        assert!(!is_valid_key("é"));
    }

    #[test]
    fn json_keys() {
        assert_eq!(keys_json(&[]), "[]");
        assert_eq!(keys_json(&["a".into(), "b".into()]), r#"["a","b"]"#);
    }
}
