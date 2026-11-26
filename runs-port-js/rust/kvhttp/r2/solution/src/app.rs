//! Request routing and handlers.

use std::sync::Arc;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Body;
use hyper::header::{CONNECTION, CONTENT_LENGTH, CONTENT_TYPE, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};

use crate::store::Store;

/// Largest accepted value, in bytes.
pub const MAX_VALUE_BYTES: usize = 1024 * 1024;
const MAX_KEY_LEN: usize = 64;

pub type HttpResponse = Response<Full<Bytes>>;

/// A request that ends in an error status with an empty body.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct HttpError(StatusCode);

type HandlerResult = Result<HttpResponse, HttpError>;

/// Shared application state; cheap to clone.
#[derive(Debug, Clone, Default)]
pub struct App {
    store: Arc<Store>,
}

impl App {
    pub fn new() -> Self {
        Self::default()
    }

    /// Handles one request. Never fails: errors become empty-bodied responses.
    pub async fn handle<B>(&self, req: Request<B>) -> HttpResponse
    where
        B: Body,
        B::Error: std::error::Error + Send + Sync + 'static,
    {
        match self.route(req).await {
            Ok(res) => res,
            Err(HttpError(status)) => {
                // Any unread request body is not worth draining; close after responding.
                let mut res = respond(status, Bytes::new(), None);
                res.headers_mut().insert(CONNECTION, HeaderValue::from_static("close"));
                res
            }
        }
    }

    async fn route<B>(&self, req: Request<B>) -> HandlerResult
    where
        B: Body,
        B::Error: std::error::Error + Send + Sync + 'static,
    {
        match req.uri().path() {
            "/health" => {
                require_get(req.method())?;
                Ok(respond(StatusCode::OK, Bytes::from_static(b"ok"), Some("text/plain; charset=utf-8")))
            }
            "/kv" => {
                require_get(req.method())?;
                Ok(respond(StatusCode::OK, keys_json(&self.store.keys()), Some("application/json")))
            }
            path => match path.strip_prefix("/kv/") {
                Some(key) => {
                    let key = key.to_owned();
                    self.handle_key(req, &key).await
                }
                None => Err(HttpError(StatusCode::NOT_FOUND)),
            },
        }
    }

    async fn handle_key<B>(&self, req: Request<B>, key: &str) -> HandlerResult
    where
        B: Body,
        B::Error: std::error::Error + Send + Sync + 'static,
    {
        if !is_valid_key(key) {
            return Err(HttpError(StatusCode::BAD_REQUEST));
        }
        match *req.method() {
            Method::GET => {
                let value = self.store.get(key).ok_or(HttpError(StatusCode::NOT_FOUND))?;
                Ok(respond(StatusCode::OK, value, Some("application/octet-stream")))
            }
            Method::PUT => {
                let value = read_body(req, MAX_VALUE_BYTES).await?;
                let status = if self.store.put(key, value) { StatusCode::OK } else { StatusCode::CREATED };
                Ok(respond(status, Bytes::new(), None))
            }
            Method::DELETE => {
                if self.store.delete(key) {
                    Ok(respond(StatusCode::NO_CONTENT, Bytes::new(), None))
                } else {
                    Err(HttpError(StatusCode::NOT_FOUND))
                }
            }
            _ => Err(HttpError(StatusCode::METHOD_NOT_ALLOWED)),
        }
    }
}

fn require_get(method: &Method) -> Result<(), HttpError> {
    if method == Method::GET { Ok(()) } else { Err(HttpError(StatusCode::METHOD_NOT_ALLOWED)) }
}

/// A key matches `[A-Za-z0-9_-]{1,64}`.
pub fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Serializes keys as a JSON array. Valid keys never need escaping.
fn keys_json(keys: &[String]) -> Bytes {
    let mut out = String::with_capacity(2 + keys.iter().map(|k| k.len() + 3).sum::<usize>());
    out.push('[');
    for (i, key) in keys.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        debug_assert!(is_valid_key(key));
        out.push('"');
        out.push_str(key);
        out.push('"');
    }
    out.push(']');
    Bytes::from(out)
}

async fn read_body<B>(req: Request<B>, limit: usize) -> Result<Bytes, HttpError>
where
    B: Body,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    let too_large = HttpError(StatusCode::PAYLOAD_TOO_LARGE);
    let declared = req
        .headers()
        .get(CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<u64>().ok());
    if declared.is_some_and(|len| len > limit as u64) {
        return Err(too_large);
    }
    match Limited::new(req.into_body(), limit).collect().await {
        Ok(collected) => Ok(collected.to_bytes()),
        Err(err) if err.is::<LengthLimitError>() => Err(too_large),
        Err(_) => Err(HttpError(StatusCode::BAD_REQUEST)),
    }
}

fn respond(status: StatusCode, body: Bytes, content_type: Option<&'static str>) -> HttpResponse {
    let mut res = Response::new(Full::new(body));
    *res.status_mut() = status;
    if let Some(ct) = content_type {
        res.headers_mut().insert(CONTENT_TYPE, HeaderValue::from_static(ct));
    }
    res
}

#[cfg(test)]
mod tests {
    use super::*;

    fn req(method: Method, path: &str, body: &'static str) -> Request<Full<Bytes>> {
        Request::builder().method(method).uri(path).body(Full::new(Bytes::from_static(body.as_bytes()))).unwrap()
    }

    async fn call(app: &App, method: Method, path: &str, body: &'static str) -> (StatusCode, Bytes) {
        let res = app.handle(req(method, path, body)).await;
        let status = res.status();
        (status, res.into_body().collect().await.unwrap().to_bytes())
    }

    #[test]
    fn key_validation() {
        assert!(is_valid_key("a-Z_09"));
        assert!(is_valid_key(&"k".repeat(64)));
        assert!(!is_valid_key(""));
        assert!(!is_valid_key(&"k".repeat(65)));
        assert!(!is_valid_key("a/b"));
        assert!(!is_valid_key("bad.key"));
    }

    #[tokio::test]
    async fn routes() {
        let app = App::new();
        assert_eq!(call(&app, Method::GET, "/health", "").await, (StatusCode::OK, Bytes::from("ok")));
        assert_eq!(call(&app, Method::POST, "/health", "").await.0, StatusCode::METHOD_NOT_ALLOWED);
        assert_eq!(call(&app, Method::GET, "/nope", "").await.0, StatusCode::NOT_FOUND);
        assert_eq!(call(&app, Method::GET, "/kv/", "").await.0, StatusCode::BAD_REQUEST);
        assert_eq!(call(&app, Method::GET, "/kv/a/b", "").await.0, StatusCode::BAD_REQUEST);
        assert_eq!(call(&app, Method::PUT, "/kv/b", "2").await.0, StatusCode::CREATED);
        assert_eq!(call(&app, Method::PUT, "/kv/a", "1").await.0, StatusCode::CREATED);
        assert_eq!(call(&app, Method::PUT, "/kv/a", "x").await.0, StatusCode::OK);
        assert_eq!(call(&app, Method::GET, "/kv/a", "").await, (StatusCode::OK, Bytes::from("x")));
        assert_eq!(call(&app, Method::PATCH, "/kv/a", "").await.0, StatusCode::METHOD_NOT_ALLOWED);
        assert_eq!(call(&app, Method::GET, "/kv", "").await, (StatusCode::OK, Bytes::from(r#"["a","b"]"#)));
        assert_eq!(call(&app, Method::DELETE, "/kv/a", "").await.0, StatusCode::NO_CONTENT);
        assert_eq!(call(&app, Method::DELETE, "/kv/a", "").await.0, StatusCode::NOT_FOUND);
        assert_eq!(call(&app, Method::GET, "/kv/a", "").await.0, StatusCode::NOT_FOUND);
    }
}
