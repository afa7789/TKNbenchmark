//! kvhttp: an in-memory HTTP/1.1 key-value server.

use std::collections::BTreeMap;
use std::convert::Infallible;
use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::header::{CONTENT_LENGTH, CONTENT_TYPE};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;
use tokio::sync::RwLock;

/// Maximum size of a stored value.
const MAX_VALUE_BYTES: usize = 1024 * 1024;
/// Maximum length of a key.
const MAX_KEY_LEN: usize = 64;

type Store = Arc<RwLock<BTreeMap<String, Bytes>>>;
type Body = Full<Bytes>;

/// Which route a request path resolves to.
enum Route<'a> {
    Health,
    List,
    Item(&'a str),
    InvalidKey,
    NotFound,
}

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn route(path: &str) -> Route<'_> {
    match path {
        "/health" => Route::Health,
        "/kv" => Route::List,
        _ => match path.strip_prefix("/kv/") {
            Some(key) if is_valid_key(key) => Route::Item(key),
            Some(_) => Route::InvalidKey,
            None => Route::NotFound,
        },
    }
}

fn respond(status: StatusCode, body: impl Into<Bytes>) -> Response<Body> {
    let mut res = Response::new(Full::new(body.into()));
    *res.status_mut() = status;
    res
}

fn empty(status: StatusCode) -> Response<Body> {
    respond(status, Bytes::new())
}

async fn read_value(req: Request<Incoming>) -> Result<Bytes, StatusCode> {
    let declared = req
        .headers()
        .get(CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<u64>().ok());
    if declared.is_some_and(|len| len > MAX_VALUE_BYTES as u64) {
        return Err(StatusCode::PAYLOAD_TOO_LARGE);
    }
    match Limited::new(req.into_body(), MAX_VALUE_BYTES).collect().await {
        Ok(collected) => Ok(collected.to_bytes()),
        Err(err) if err.is::<LengthLimitError>() => Err(StatusCode::PAYLOAD_TOO_LARGE),
        Err(_) => Err(StatusCode::BAD_REQUEST),
    }
}

async fn handle(store: Store, req: Request<Incoming>) -> Result<Response<Body>, Infallible> {
    let path = req.uri().path().to_owned();
    let method = req.method().clone();

    let res = match (route(&path), method) {
        (Route::Health, Method::GET) => respond(StatusCode::OK, "ok"),
        (Route::List, Method::GET) => {
            let keys: Vec<String> = store.read().await.keys().cloned().collect();
            let json = serde_json::to_vec(&keys).expect("serializing strings cannot fail");
            let mut res = respond(StatusCode::OK, json);
            res.headers_mut()
                .insert(CONTENT_TYPE, "application/json".parse().expect("static header"));
            res
        }
        (Route::Item(key), Method::GET) => match store.read().await.get(key) {
            Some(value) => respond(StatusCode::OK, value.clone()),
            None => empty(StatusCode::NOT_FOUND),
        },
        (Route::Item(key), Method::PUT) => {
            let key = key.to_owned();
            match read_value(req).await {
                Ok(value) => match store.write().await.insert(key, value) {
                    Some(_) => empty(StatusCode::OK),
                    None => empty(StatusCode::CREATED),
                },
                Err(status) => empty(status),
            }
        }
        (Route::Item(key), Method::DELETE) => match store.write().await.remove(key) {
            Some(_) => empty(StatusCode::NO_CONTENT),
            None => empty(StatusCode::NOT_FOUND),
        },
        (Route::InvalidKey, _) => empty(StatusCode::BAD_REQUEST),
        (Route::NotFound, _) => empty(StatusCode::NOT_FOUND),
        (Route::Health | Route::List | Route::Item(_), _) => {
            empty(StatusCode::METHOD_NOT_ALLOWED)
        }
    };
    Ok(res)
}

#[tokio::main]
async fn main() -> ExitCode {
    let port = match std::env::args().nth(1).map(|p| p.parse::<u16>()) {
        Some(Ok(port)) => port,
        _ => {
            eprintln!("usage: app <port>");
            return ExitCode::from(2);
        }
    };

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = match TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("failed to bind {addr}: {err}");
            return ExitCode::FAILURE;
        }
    };

    let store: Store = Arc::default();
    loop {
        let stream = match listener.accept().await {
            Ok((stream, _)) => stream,
            Err(err) => {
                eprintln!("accept error: {err}");
                continue;
            }
        };
        let _ = stream.set_nodelay(true);
        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| handle(Arc::clone(&store), req));
            if let Err(err) = http1::Builder::new()
                .serve_connection(TokioIo::new(stream), service)
                .await
            {
                eprintln!("connection error: {err}");
            }
        });
    }
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
    fn routing() {
        assert!(matches!(route("/health"), Route::Health));
        assert!(matches!(route("/kv"), Route::List));
        assert!(matches!(route("/kv/abc"), Route::Item("abc")));
        assert!(matches!(route("/kv/"), Route::InvalidKey));
        assert!(matches!(route("/kv/a/b"), Route::InvalidKey));
        assert!(matches!(route("/kvx"), Route::NotFound));
        assert!(matches!(route("/"), Route::NotFound));
    }
}
