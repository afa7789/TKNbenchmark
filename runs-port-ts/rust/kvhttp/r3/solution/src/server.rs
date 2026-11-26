//! HTTP routing and request handling.

use std::sync::Arc;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::header::{ALLOW, CONTENT_LENGTH, CONTENT_TYPE, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};

use crate::store::KvStore;

pub const MAX_VALUE_BYTES: usize = 1024 * 1024;
const KV_PREFIX: &str = "/kv/";
const MAX_KEY_LEN: usize = 64;

const TEXT_PLAIN: &str = "text/plain; charset=utf-8";
const OCTET_STREAM: &str = "application/octet-stream";
const JSON: &str = "application/json";

/// A request failure that maps directly onto an HTTP error response.
#[derive(Debug)]
enum HttpError {
    BadRequest(&'static str),
    NotFound,
    MethodNotAllowed(&'static str),
    PayloadTooLarge,
    Internal,
}

impl HttpError {
    fn into_response(self) -> Response<Full<Bytes>> {
        let (status, message) = match self {
            Self::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            Self::NotFound => (StatusCode::NOT_FOUND, "Not Found"),
            Self::MethodNotAllowed(_) => (StatusCode::METHOD_NOT_ALLOWED, "Method Not Allowed"),
            Self::PayloadTooLarge => (StatusCode::PAYLOAD_TOO_LARGE, "Payload Too Large"),
            Self::Internal => (StatusCode::INTERNAL_SERVER_ERROR, "internal error"),
        };
        let mut res = respond(status, Bytes::from_static(message.as_bytes()), TEXT_PLAIN);
        if let Self::MethodNotAllowed(allowed) = self {
            res.headers_mut()
                .insert(ALLOW, HeaderValue::from_static(allowed));
        }
        res
    }
}

/// Builds a response with an explicit `Content-Length`, and a `Content-Type` when non-empty.
fn respond(status: StatusCode, body: Bytes, content_type: &'static str) -> Response<Full<Bytes>> {
    let len = body.len();
    let mut res = Response::new(Full::new(body));
    *res.status_mut() = status;
    let headers = res.headers_mut();
    headers.insert(CONTENT_LENGTH, HeaderValue::from(len));
    if len > 0 {
        headers.insert(CONTENT_TYPE, HeaderValue::from_static(content_type));
    }
    res
}

fn empty(status: StatusCode) -> Response<Full<Bytes>> {
    respond(status, Bytes::new(), TEXT_PLAIN)
}

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

async fn read_body(body: Incoming, declared: Option<&HeaderValue>) -> Result<Bytes, HttpError> {
    let declared = declared
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<u64>().ok());
    if declared.is_some_and(|len| len > MAX_VALUE_BYTES as u64) {
        return Err(HttpError::PayloadTooLarge);
    }
    match Limited::new(body, MAX_VALUE_BYTES).collect().await {
        Ok(collected) => Ok(collected.to_bytes()),
        Err(err) if err.is::<LengthLimitError>() => Err(HttpError::PayloadTooLarge),
        Err(_) => Err(HttpError::BadRequest("invalid body")),
    }
}

async fn route(
    store: &KvStore,
    req: Request<Incoming>,
) -> Result<Response<Full<Bytes>>, HttpError> {
    let path = req.uri().path();

    match path {
        "/health" => {
            if req.method() != Method::GET {
                return Err(HttpError::MethodNotAllowed("GET"));
            }
            Ok(respond(
                StatusCode::OK,
                Bytes::from_static(b"ok"),
                TEXT_PLAIN,
            ))
        }
        "/kv" => {
            if req.method() != Method::GET {
                return Err(HttpError::MethodNotAllowed("GET"));
            }
            let json = serde_json::to_vec(&store.keys()).map_err(|_| HttpError::Internal)?;
            Ok(respond(StatusCode::OK, json.into(), JSON))
        }
        _ => {
            let Some(key) = path.strip_prefix(KV_PREFIX) else {
                return Err(HttpError::NotFound);
            };
            if !is_valid_key(key) {
                return Err(HttpError::BadRequest("invalid key"));
            }
            let key = key.to_owned();

            match *req.method() {
                Method::GET => {
                    let value = store.get(&key).ok_or(HttpError::NotFound)?;
                    Ok(respond(StatusCode::OK, value, OCTET_STREAM))
                }
                Method::PUT => {
                    let (parts, body) = req.into_parts();
                    let value = read_body(body, parts.headers.get(CONTENT_LENGTH)).await?;
                    let status = if store.set(&key, value) {
                        StatusCode::CREATED
                    } else {
                        StatusCode::OK
                    };
                    Ok(empty(status))
                }
                Method::DELETE => {
                    if store.delete(&key) {
                        Ok(empty(StatusCode::NO_CONTENT))
                    } else {
                        Err(HttpError::NotFound)
                    }
                }
                _ => Err(HttpError::MethodNotAllowed("GET, PUT, DELETE")),
            }
        }
    }
}

/// Handles a single request, converting routing errors into HTTP responses.
pub async fn handle(
    store: Arc<KvStore>,
    req: Request<Incoming>,
) -> Result<Response<Full<Bytes>>, std::convert::Infallible> {
    Ok(route(&store, req)
        .await
        .unwrap_or_else(HttpError::into_response))
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
        assert!(!is_valid_key("é"));
    }
}
