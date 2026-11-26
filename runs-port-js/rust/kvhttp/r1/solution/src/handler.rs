//! Request routing and the route handlers.

use std::convert::Infallible;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::header::{self, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};

use crate::store::Store;

/// Largest accepted value, in bytes.
pub const MAX_VALUE_BYTES: usize = 1024 * 1024;
const MAX_KEY_LEN: usize = 64;
const KV_PREFIX: &str = "/kv/";

const TEXT_PLAIN: &str = "text/plain; charset=utf-8";
const OCTET_STREAM: &str = "application/octet-stream";
const APPLICATION_JSON: &str = "application/json";

type Body = Full<Bytes>;

/// A request that could not be served, mapped onto an error response.
#[derive(Debug)]
enum HttpError {
    BadRequest,
    NotFound,
    MethodNotAllowed { allow: &'static str },
    PayloadTooLarge,
}

impl HttpError {
    fn into_response(self) -> Response<Body> {
        let status = match self {
            Self::BadRequest => StatusCode::BAD_REQUEST,
            Self::NotFound => StatusCode::NOT_FOUND,
            Self::MethodNotAllowed { .. } => StatusCode::METHOD_NOT_ALLOWED,
            Self::PayloadTooLarge => StatusCode::PAYLOAD_TOO_LARGE,
        };
        let reason = status.canonical_reason().unwrap_or_default();
        let mut res = response(status, Bytes::from_static(reason.as_bytes()), Some(TEXT_PLAIN));
        let headers = res.headers_mut();
        match self {
            Self::MethodNotAllowed { allow } => {
                headers.insert(header::ALLOW, HeaderValue::from_static(allow));
            }
            Self::PayloadTooLarge => {
                headers.insert(header::CONNECTION, HeaderValue::from_static("close"));
            }
            Self::BadRequest | Self::NotFound => {}
        }
        res
    }
}

/// Entry point for every request; never fails at the service level.
pub async fn handle(store: &Store, req: Request<Incoming>) -> Result<Response<Body>, Infallible> {
    Ok(route(store, req).await.unwrap_or_else(HttpError::into_response))
}

async fn route(store: &Store, req: Request<Incoming>) -> Result<Response<Body>, HttpError> {
    let (parts, body) = req.into_parts();
    // Always drain the body first so error responses don't reset the connection.
    let body = read_body(&parts.headers, body).await?;
    let method = &parts.method;

    match parts.uri.path() {
        "/health" => health(method),
        "/kv" => list(store, method),
        path => match path.strip_prefix(KV_PREFIX) {
            Some(key) if is_valid_key(key) => item(store, method, key, body),
            Some(_) => Err(HttpError::BadRequest),
            None => Err(HttpError::NotFound),
        },
    }
}

async fn read_body(headers: &hyper::HeaderMap, body: Incoming) -> Result<Bytes, HttpError> {
    let declared = headers
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<u64>().ok());
    if declared.is_some_and(|len| len > MAX_VALUE_BYTES as u64) {
        return Err(HttpError::PayloadTooLarge);
    }

    match Limited::new(body, MAX_VALUE_BYTES).collect().await {
        Ok(collected) => Ok(collected.to_bytes()),
        Err(err) if err.is::<LengthLimitError>() => Err(HttpError::PayloadTooLarge),
        // The client went away or sent a malformed body.
        Err(_) => Err(HttpError::BadRequest),
    }
}

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn health(method: &Method) -> Result<Response<Body>, HttpError> {
    if method != Method::GET {
        return Err(HttpError::MethodNotAllowed { allow: "GET" });
    }
    Ok(response(StatusCode::OK, Bytes::from_static(b"ok"), Some(TEXT_PLAIN)))
}

fn list(store: &Store, method: &Method) -> Result<Response<Body>, HttpError> {
    if method != Method::GET {
        return Err(HttpError::MethodNotAllowed { allow: "GET" });
    }
    let keys = store.keys();
    // Valid keys contain only `[A-Za-z0-9_-]`, so they need no JSON escaping.
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
    Ok(response(StatusCode::OK, Bytes::from(json), Some(APPLICATION_JSON)))
}

fn item(store: &Store, method: &Method, key: &str, body: Bytes) -> Result<Response<Body>, HttpError> {
    match *method {
        Method::GET => {
            let value = store.get(key).ok_or(HttpError::NotFound)?;
            Ok(response(StatusCode::OK, value, Some(OCTET_STREAM)))
        }
        Method::PUT => {
            let status = if store.put(key, body) { StatusCode::CREATED } else { StatusCode::OK };
            Ok(response(status, Bytes::new(), None))
        }
        Method::DELETE => {
            if !store.delete(key) {
                return Err(HttpError::NotFound);
            }
            Ok(response(StatusCode::NO_CONTENT, Bytes::new(), None))
        }
        _ => Err(HttpError::MethodNotAllowed { allow: "GET, PUT, DELETE" }),
    }
}

fn response(status: StatusCode, body: Bytes, content_type: Option<&'static str>) -> Response<Body> {
    let mut res = Response::new(Full::new(body));
    *res.status_mut() = status;
    if let Some(content_type) = content_type {
        res.headers_mut()
            .insert(header::CONTENT_TYPE, HeaderValue::from_static(content_type));
    }
    res
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
        assert!(!is_valid_key("%41"));
        assert!(!is_valid_key("é"));
    }
}
