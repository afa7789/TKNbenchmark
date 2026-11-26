//! HTTP routing and the in-memory store.

use std::collections::BTreeMap;
use std::convert::Infallible;
use std::sync::{Arc, PoisonError, RwLock};
use std::time::Duration;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::header::{self, HeaderValue};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::{TokioIo, TokioTimer};
use tokio::net::TcpListener;

/// Largest accepted value, in bytes.
pub const MAX_VALUE_BYTES: usize = 1024 * 1024;
const MAX_KEY_LEN: usize = 64;

/// Shared key-value store. A `BTreeMap` keeps keys sorted for listing.
#[derive(Clone, Default)]
pub struct Store(Arc<RwLock<BTreeMap<String, Bytes>>>);

impl Store {
    fn get(&self, key: &str) -> Option<Bytes> {
        self.0
            .read()
            .unwrap_or_else(PoisonError::into_inner)
            .get(key)
            .cloned()
    }

    /// Stores `value`, returning whether the key already existed.
    fn put(&self, key: &str, value: Bytes) -> bool {
        self.0
            .write()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(key.to_owned(), value)
            .is_some()
    }

    /// Removes `key`, returning whether it was present.
    fn delete(&self, key: &str) -> bool {
        self.0
            .write()
            .unwrap_or_else(PoisonError::into_inner)
            .remove(key)
            .is_some()
    }

    fn keys(&self) -> Vec<String> {
        self.0
            .read()
            .unwrap_or_else(PoisonError::into_inner)
            .keys()
            .cloned()
            .collect()
    }
}

/// Accepts connections forever, serving each on its own task.
pub async fn serve(listener: TcpListener, store: Store) {
    loop {
        let stream = match listener.accept().await {
            Ok((stream, _)) => stream,
            Err(err) => {
                // Transient failures (e.g. EMFILE) must not stop the server.
                eprintln!("kvhttp: accept failed: {err}");
                tokio::time::sleep(Duration::from_millis(10)).await;
                continue;
            }
        };
        let _ = stream.set_nodelay(true);
        let store = store.clone();
        tokio::spawn(async move {
            let service = service_fn(move |req| {
                let store = store.clone();
                async move { Ok::<_, Infallible>(handle(req, &store).await) }
            });
            let conn = http1::Builder::new()
                .timer(TokioTimer::new())
                .header_read_timeout(Duration::from_secs(30))
                .serve_connection(TokioIo::new(stream), service);
            if let Err(err) = conn.await
                && !err.is_incomplete_message()
            {
                eprintln!("kvhttp: connection error: {err}");
            }
        });
    }
}

type Resp = Response<Full<Bytes>>;

async fn handle(req: Request<Incoming>, store: &Store) -> Resp {
    let path = req.uri().path();
    let method = req.method();

    match path {
        "/health" => match *method {
            Method::GET => text(StatusCode::OK, "ok"),
            _ => method_not_allowed("GET"),
        },
        "/kv" => match *method {
            Method::GET => list(store),
            _ => method_not_allowed("GET"),
        },
        _ => {
            let Some(key) = path.strip_prefix("/kv/") else {
                return error(StatusCode::NOT_FOUND);
            };
            if !is_valid_key(key) {
                return error(StatusCode::BAD_REQUEST);
            }
            let key = key.to_owned();
            match *method {
                Method::GET => match store.get(&key) {
                    Some(value) => respond(StatusCode::OK, value, Some("application/octet-stream")),
                    None => error(StatusCode::NOT_FOUND),
                },
                Method::PUT => put(req, &key, store).await,
                Method::DELETE if store.delete(&key) => empty(StatusCode::NO_CONTENT),
                Method::DELETE => error(StatusCode::NOT_FOUND),
                _ => method_not_allowed("GET, PUT, DELETE"),
            }
        }
    }
}

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

async fn put(req: Request<Incoming>, key: &str, store: &Store) -> Resp {
    let declared = req
        .headers()
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok());
    if declared.is_some_and(|len| len > MAX_VALUE_BYTES as u64) {
        return too_large();
    }

    let value = match Limited::new(req.into_body(), MAX_VALUE_BYTES)
        .collect()
        .await
    {
        Ok(collected) => collected.to_bytes(),
        Err(err) if err.is::<LengthLimitError>() => return too_large(),
        Err(_) => return error(StatusCode::BAD_REQUEST),
    };

    let status = if store.put(key, value) {
        StatusCode::OK
    } else {
        StatusCode::CREATED
    };
    empty(status)
}

fn list(store: &Store) -> Resp {
    // Keys are restricted to [A-Za-z0-9_-], so they need no JSON escaping.
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
    respond(StatusCode::OK, Bytes::from(json), Some("application/json"))
}

fn respond(status: StatusCode, body: Bytes, content_type: Option<&'static str>) -> Resp {
    let mut builder = Response::builder().status(status);
    if let Some(ct) = content_type.filter(|_| !body.is_empty()) {
        builder = builder.header(header::CONTENT_TYPE, ct);
    }
    // hyper sets Content-Length from the full body (and omits it for 204).
    builder.body(Full::new(body)).expect("valid response")
}

fn text(status: StatusCode, body: &'static str) -> Resp {
    respond(
        status,
        Bytes::from_static(body.as_bytes()),
        Some("text/plain; charset=utf-8"),
    )
}

fn empty(status: StatusCode) -> Resp {
    respond(status, Bytes::new(), None)
}

fn error(status: StatusCode) -> Resp {
    text(status, status.canonical_reason().unwrap_or("Error"))
}

fn method_not_allowed(allow: &'static str) -> Resp {
    let mut resp = error(StatusCode::METHOD_NOT_ALLOWED);
    resp.headers_mut()
        .insert(header::ALLOW, HeaderValue::from_static(allow));
    resp
}

fn too_large() -> Resp {
    let mut resp = error(StatusCode::PAYLOAD_TOO_LARGE);
    resp.headers_mut()
        .insert(header::CONNECTION, HeaderValue::from_static("close"));
    resp
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
        assert!(!is_valid_key("a%20b"));
    }
}
