//! HTTP routing and connection handling.

use std::convert::Infallible;
use std::sync::Arc;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::header::{ALLOW, CONTENT_LENGTH, CONTENT_TYPE, HeaderValue};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

use crate::store::KvStore;

/// Largest value accepted by `PUT /kv/<key>`.
pub const MAX_VALUE_BYTES: usize = 1024 * 1024;
const KV_PREFIX: &str = "/kv/";
const MAX_KEY_LEN: usize = 64;

type Body = Full<Bytes>;

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn respond(status: StatusCode, body: impl Into<Bytes>) -> Response<Body> {
    let mut res = Response::new(Full::new(body.into()));
    *res.status_mut() = status;
    res
}

fn empty(status: StatusCode) -> Response<Body> {
    respond(status, Bytes::new())
}

fn with_type(mut res: Response<Body>, content_type: &'static str) -> Response<Body> {
    res.headers_mut()
        .insert(CONTENT_TYPE, HeaderValue::from_static(content_type));
    res
}

fn method_not_allowed(allowed: &'static str) -> Response<Body> {
    let mut res = empty(StatusCode::METHOD_NOT_ALLOWED);
    res.headers_mut()
        .insert(ALLOW, HeaderValue::from_static(allowed));
    res
}

enum BodyError {
    TooLarge,
    Io,
}

/// Reads the full request body, rejecting bodies larger than `limit` bytes.
async fn read_body(req: Request<Incoming>, limit: usize) -> Result<Bytes, BodyError> {
    let declared = req
        .headers()
        .get(CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<u64>().ok());
    if declared.is_some_and(|len| len > limit as u64) {
        return Err(BodyError::TooLarge);
    }
    match Limited::new(req.into_body(), limit).collect().await {
        Ok(collected) => Ok(collected.to_bytes()),
        Err(err) if err.is::<LengthLimitError>() => Err(BodyError::TooLarge),
        Err(_) => Err(BodyError::Io),
    }
}

async fn handle_key(store: &KvStore, req: Request<Incoming>, key: &str) -> Response<Body> {
    match *req.method() {
        Method::GET => match store.get(key) {
            Some(value) => with_type(respond(StatusCode::OK, value), "application/octet-stream"),
            None => empty(StatusCode::NOT_FOUND),
        },
        Method::PUT => match read_body(req, MAX_VALUE_BYTES).await {
            Ok(value) => {
                let created = store.put(key, value);
                empty(if created {
                    StatusCode::CREATED
                } else {
                    StatusCode::OK
                })
            }
            Err(BodyError::TooLarge) => empty(StatusCode::PAYLOAD_TOO_LARGE),
            Err(BodyError::Io) => empty(StatusCode::BAD_REQUEST),
        },
        Method::DELETE if store.delete(key) => empty(StatusCode::NO_CONTENT),
        Method::DELETE => empty(StatusCode::NOT_FOUND),
        _ => method_not_allowed("GET, PUT, DELETE"),
    }
}

async fn route(store: &KvStore, req: Request<Incoming>) -> Response<Body> {
    let path = req.uri().path().to_owned();

    match path.as_str() {
        "/health" => match *req.method() {
            Method::GET => with_type(respond(StatusCode::OK, "ok"), "text/plain"),
            _ => method_not_allowed("GET"),
        },
        "/kv" => match *req.method() {
            Method::GET => {
                let json = serde_json::to_vec(&store.keys()).expect("keys serialize to JSON");
                with_type(respond(StatusCode::OK, json), "application/json")
            }
            _ => method_not_allowed("GET"),
        },
        _ => match path.strip_prefix(KV_PREFIX) {
            Some(key) if is_valid_key(key) => handle_key(store, req, key).await,
            Some(_) => empty(StatusCode::BAD_REQUEST),
            None => empty(StatusCode::NOT_FOUND),
        },
    }
}

/// Accepts connections forever, serving each on its own task.
pub async fn serve(listener: TcpListener, store: Arc<KvStore>) -> std::io::Result<()> {
    loop {
        let (stream, _) = match listener.accept().await {
            Ok(conn) => conn,
            Err(err) => {
                // Transient failures (e.g. fd exhaustion) must not stop the server.
                eprintln!("accept error: {err}");
                tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                continue;
            }
        };
        let _ = stream.set_nodelay(true);
        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| {
                let store = Arc::clone(&store);
                async move { Ok::<_, Infallible>(route(&store, req).await) }
            });
            // Every response closes the connection; any unread body is discarded.
            let conn = http1::Builder::new()
                .keep_alive(false)
                .serve_connection(TokioIo::new(stream), service);
            if let Err(err) = conn.await
                && !err.is_incomplete_message()
            {
                eprintln!("connection error: {err}");
            }
        });
    }
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
