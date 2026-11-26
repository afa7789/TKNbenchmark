//! Request routing for the key-value API.

use std::sync::Arc;
use std::time::Duration;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::header::{CONTENT_TYPE, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};

use crate::store::{PutOutcome, Store};

/// Largest accepted request body (and therefore stored value).
pub const MAX_VALUE: usize = 1024 * 1024;
/// Longest accepted key.
pub const KEY_MAX: usize = 64;
/// How long a client may take to deliver the request body.
const BODY_TIMEOUT: Duration = Duration::from_secs(30);

pub type BoxError = Box<dyn std::error::Error + Send + Sync>;

/// Handles one request. An `Err` means the client went away or stalled, and
/// the connection is dropped without a response.
pub async fn handle(
    store: Arc<Store>,
    req: Request<Incoming>,
) -> Result<Response<Full<Bytes>>, BoxError> {
    let (parts, body) = req.into_parts();
    let collected =
        tokio::time::timeout(BODY_TIMEOUT, Limited::new(body, MAX_VALUE).collect()).await?;
    let body = match collected {
        Ok(collected) => collected.to_bytes(),
        Err(err) if err.is::<LengthLimitError>() => {
            return Ok(empty(StatusCode::PAYLOAD_TOO_LARGE));
        }
        Err(err) => return Err(err),
    };
    Ok(route(&store, &parts.method, parts.uri.path(), body))
}

fn route(store: &Store, method: &Method, path: &str, body: Bytes) -> Response<Full<Bytes>> {
    match path {
        "/health" => match *method {
            Method::GET => with_type(StatusCode::OK, "text/plain", Bytes::from_static(b"ok")),
            _ => empty(StatusCode::METHOD_NOT_ALLOWED),
        },
        "/kv" => match *method {
            Method::GET => with_type(
                StatusCode::OK,
                "application/json",
                list_json(&store.keys()).into(),
            ),
            _ => empty(StatusCode::METHOD_NOT_ALLOWED),
        },
        _ => match path.strip_prefix("/kv/") {
            Some(key) if is_valid_key(key) => handle_key(store, method, key, body),
            Some(_) => empty(StatusCode::BAD_REQUEST),
            None => empty(StatusCode::NOT_FOUND),
        },
    }
}

fn handle_key(store: &Store, method: &Method, key: &str, body: Bytes) -> Response<Full<Bytes>> {
    match *method {
        Method::GET => match store.get(key) {
            Some(value) => with_type(StatusCode::OK, "application/octet-stream", value),
            None => empty(StatusCode::NOT_FOUND),
        },
        Method::PUT => match store.put(key, body) {
            PutOutcome::Created => empty(StatusCode::CREATED),
            PutOutcome::Replaced => empty(StatusCode::OK),
        },
        Method::DELETE if store.delete(key) => empty(StatusCode::NO_CONTENT),
        Method::DELETE => empty(StatusCode::NOT_FOUND),
        _ => empty(StatusCode::METHOD_NOT_ALLOWED),
    }
}

/// A key matches `[A-Za-z0-9_-]{1,64}`.
fn is_valid_key(key: &str) -> bool {
    (1..=KEY_MAX).contains(&key.len())
        && key
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
}

/// Renders keys as a JSON array. Valid keys never need escaping.
fn list_json(keys: &[String]) -> String {
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

fn empty(status: StatusCode) -> Response<Full<Bytes>> {
    let mut res = Response::new(Full::default());
    *res.status_mut() = status;
    res
}

fn with_type(status: StatusCode, content_type: &'static str, body: Bytes) -> Response<Full<Bytes>> {
    let mut res = Response::new(Full::new(body));
    *res.status_mut() = status;
    res.headers_mut()
        .insert(CONTENT_TYPE, HeaderValue::from_static(content_type));
    res
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_validation() {
        assert!(is_valid_key("a"));
        assert!(is_valid_key("A-z_09"));
        assert!(is_valid_key(&"k".repeat(KEY_MAX)));
        assert!(!is_valid_key(""));
        assert!(!is_valid_key(&"k".repeat(KEY_MAX + 1)));
        assert!(!is_valid_key("a/b"));
        assert!(!is_valid_key("bad.key"));
        assert!(!is_valid_key("%41"));
        assert!(!is_valid_key("é"));
    }

    #[test]
    fn routing_statuses() {
        let store = Store::new();
        let status = |m: Method, p: &str| route(&store, &m, p, Bytes::new()).status();
        assert_eq!(status(Method::GET, "/health"), StatusCode::OK);
        assert_eq!(
            status(Method::POST, "/health"),
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(status(Method::GET, "/nope"), StatusCode::NOT_FOUND);
        assert_eq!(status(Method::GET, "/kv/"), StatusCode::BAD_REQUEST);
        assert_eq!(status(Method::GET, "/kv/a/b"), StatusCode::BAD_REQUEST);
        assert_eq!(
            status(Method::PATCH, "/kv/a"),
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(status(Method::POST, "/kv"), StatusCode::METHOD_NOT_ALLOWED);
        assert_eq!(status(Method::PUT, "/kv/a"), StatusCode::CREATED);
        assert_eq!(status(Method::PUT, "/kv/a"), StatusCode::OK);
        assert_eq!(status(Method::DELETE, "/kv/a"), StatusCode::NO_CONTENT);
        assert_eq!(status(Method::DELETE, "/kv/a"), StatusCode::NOT_FOUND);
    }

    #[test]
    fn json_listing() {
        assert_eq!(list_json(&[]), "[]");
        assert_eq!(list_json(&["a".into(), "b".into()]), r#"["a","b"]"#);
    }
}
