//! HTTP routing and request handling.

use std::convert::Infallible;
use std::sync::Arc;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Body;
use hyper::header::{self, HeaderValue};
use hyper::{Method, Request, Response, StatusCode};

use crate::store::Store;

/// Largest accepted value, in bytes.
pub const MAX_VALUE_BYTES: usize = 1 << 20;
const MAX_KEY_LEN: usize = 64;
const KV_PREFIX: &str = "/kv/";

const TEXT_PLAIN: HeaderValue = HeaderValue::from_static("text/plain; charset=utf-8");
const APPLICATION_JSON: HeaderValue = HeaderValue::from_static("application/json");

/// Returns whether `key` matches `[A-Za-z0-9_-]{1,64}`.
pub fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Handles a single request against `store`.
pub async fn handle<B>(
    store: Arc<Store>,
    req: Request<B>,
) -> Result<Response<Full<Bytes>>, Infallible>
where
    B: Body<Data = Bytes>,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    let response = match req.uri().path() {
        "/health" => match *req.method() {
            Method::GET => text(StatusCode::OK, "ok"),
            _ => status(StatusCode::METHOD_NOT_ALLOWED),
        },
        "/kv" => match *req.method() {
            Method::GET => list_keys(&store),
            _ => status(StatusCode::METHOD_NOT_ALLOWED),
        },
        path => match path.strip_prefix(KV_PREFIX) {
            Some(key) if !is_valid_key(key) => status(StatusCode::BAD_REQUEST),
            Some(key) => {
                let key = key.to_owned();
                match *req.method() {
                    Method::GET => match store.get(&key) {
                        Some(value) => Response::new(Full::new(value)),
                        None => status(StatusCode::NOT_FOUND),
                    },
                    Method::PUT => put(&store, &key, req).await,
                    Method::DELETE if store.remove(&key) => status(StatusCode::NO_CONTENT),
                    Method::DELETE => status(StatusCode::NOT_FOUND),
                    _ => status(StatusCode::METHOD_NOT_ALLOWED),
                }
            }
            None => status(StatusCode::NOT_FOUND),
        },
    };
    Ok(response)
}

async fn put<B>(store: &Store, key: &str, req: Request<B>) -> Response<Full<Bytes>>
where
    B: Body<Data = Bytes>,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    if let Some(declared) = req.headers().get(header::CONTENT_LENGTH) {
        match declared
            .to_str()
            .ok()
            .and_then(|s| s.trim().parse::<u64>().ok())
        {
            Some(len) if len > MAX_VALUE_BYTES as u64 => {
                return status(StatusCode::PAYLOAD_TOO_LARGE);
            }
            Some(_) => {}
            None => return status(StatusCode::BAD_REQUEST),
        }
    }

    let value = match Limited::new(req.into_body(), MAX_VALUE_BYTES)
        .collect()
        .await
    {
        Ok(collected) => collected.to_bytes(),
        Err(err) if err.is::<LengthLimitError>() => return status(StatusCode::PAYLOAD_TOO_LARGE),
        Err(_) => return status(StatusCode::BAD_REQUEST),
    };

    if store.put(key, value) {
        status(StatusCode::CREATED)
    } else {
        status(StatusCode::OK)
    }
}

fn list_keys(store: &Store) -> Response<Full<Bytes>> {
    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
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
    with_type(StatusCode::OK, APPLICATION_JSON, json)
}

fn status(code: StatusCode) -> Response<Full<Bytes>> {
    let mut response = Response::new(Full::default());
    *response.status_mut() = code;
    response
}

fn text(code: StatusCode, body: &'static str) -> Response<Full<Bytes>> {
    with_type(code, TEXT_PLAIN, body)
}

fn with_type(
    code: StatusCode,
    content_type: HeaderValue,
    body: impl Into<Bytes>,
) -> Response<Full<Bytes>> {
    let mut response = Response::new(Full::new(body.into()));
    *response.status_mut() = code;
    response
        .headers_mut()
        .insert(header::CONTENT_TYPE, content_type);
    response
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn call(
        store: &Arc<Store>,
        method: &str,
        path: &str,
        body: &'static str,
    ) -> (StatusCode, Bytes) {
        let req = Request::builder()
            .method(method)
            .uri(path)
            .body(Full::new(Bytes::from_static(body.as_bytes())))
            .unwrap();
        let res = handle(Arc::clone(store), req).await.unwrap();
        let status = res.status();
        (status, res.into_body().collect().await.unwrap().to_bytes())
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
        assert!(!is_valid_key("a%20b"));
    }

    #[tokio::test]
    async fn routes() {
        let store = Arc::new(Store::new());
        assert_eq!(
            call(&store, "GET", "/health", "").await,
            (StatusCode::OK, Bytes::from("ok"))
        );
        assert_eq!(
            call(&store, "POST", "/health", "").await.0,
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(
            call(&store, "GET", "/nope", "").await.0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            call(&store, "GET", "/kv/", "").await.0,
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            call(&store, "GET", "/kv/a/b", "").await.0,
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            call(&store, "PUT", "/kv/b", "2").await.0,
            StatusCode::CREATED
        );
        assert_eq!(
            call(&store, "PUT", "/kv/a", "1").await.0,
            StatusCode::CREATED
        );
        assert_eq!(call(&store, "PUT", "/kv/a", "x").await.0, StatusCode::OK);
        assert_eq!(
            call(&store, "GET", "/kv/a", "").await,
            (StatusCode::OK, Bytes::from("x"))
        );
        assert_eq!(
            call(&store, "PATCH", "/kv/a", "").await.0,
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(
            call(&store, "POST", "/kv", "").await.0,
            StatusCode::METHOD_NOT_ALLOWED
        );
        assert_eq!(
            call(&store, "GET", "/kv", "").await,
            (StatusCode::OK, Bytes::from(r#"["a","b"]"#))
        );
        assert_eq!(
            call(&store, "DELETE", "/kv/a", "").await.0,
            StatusCode::NO_CONTENT
        );
        assert_eq!(
            call(&store, "DELETE", "/kv/a", "").await.0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            call(&store, "GET", "/kv/a", "").await.0,
            StatusCode::NOT_FOUND
        );
    }
}
