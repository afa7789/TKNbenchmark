//! kvhttp: an in-memory HTTP/1.1 key-value server.

use std::collections::BTreeMap;
use std::convert::Infallible;
use std::net::{Ipv4Addr, SocketAddr};
use std::sync::{Arc, RwLock};

use anyhow::{Context, Result};
use bytes::Bytes;
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::header::{CONTENT_TYPE, HeaderValue};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

/// Largest accepted value, in bytes.
const MAX_VALUE_LEN: usize = 1024 * 1024;
/// Longest accepted key, in bytes.
const MAX_KEY_LEN: usize = 64;

type Store = Arc<RwLock<BTreeMap<String, Bytes>>>;

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn response(status: StatusCode, body: impl Into<Bytes>) -> Response<Full<Bytes>> {
    let mut res = Response::new(Full::new(body.into()));
    *res.status_mut() = status;
    res
}

fn empty(status: StatusCode) -> Response<Full<Bytes>> {
    response(status, Bytes::new())
}

async fn handle(req: Request<Incoming>, store: Store) -> Result<Response<Full<Bytes>>, Infallible> {
    let path = req.uri().path().to_owned();
    let res = match path.as_str() {
        "/health" => match *req.method() {
            Method::GET => response(StatusCode::OK, "ok"),
            _ => empty(StatusCode::METHOD_NOT_ALLOWED),
        },
        "/kv" => match *req.method() {
            Method::GET => list_keys(&store),
            _ => empty(StatusCode::METHOD_NOT_ALLOWED),
        },
        _ => match path.strip_prefix("/kv/") {
            Some(key) if !is_valid_key(key) => empty(StatusCode::BAD_REQUEST),
            Some(key) => handle_key(req, key, &store).await,
            None => empty(StatusCode::NOT_FOUND),
        },
    };
    Ok(res)
}

fn list_keys(store: &Store) -> Response<Full<Bytes>> {
    let body = {
        let map = store
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        serde_json::to_vec(&map.keys().collect::<Vec<_>>())
    };
    match body {
        Ok(body) => {
            let mut res = response(StatusCode::OK, body);
            res.headers_mut()
                .insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
            res
        }
        Err(_) => empty(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

async fn handle_key(req: Request<Incoming>, key: &str, store: &Store) -> Response<Full<Bytes>> {
    match *req.method() {
        Method::GET => {
            let value = store
                .read()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .get(key)
                .cloned();
            match value {
                Some(value) => response(StatusCode::OK, value),
                None => empty(StatusCode::NOT_FOUND),
            }
        }
        Method::PUT => {
            let value = match Limited::new(req.into_body(), MAX_VALUE_LEN).collect().await {
                Ok(collected) => collected.to_bytes(),
                Err(err) if err.is::<LengthLimitError>() => {
                    return empty(StatusCode::PAYLOAD_TOO_LARGE);
                }
                Err(_) => return empty(StatusCode::BAD_REQUEST),
            };
            let previous = store
                .write()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .insert(key.to_owned(), value);
            empty(if previous.is_some() {
                StatusCode::OK
            } else {
                StatusCode::CREATED
            })
        }
        Method::DELETE => {
            let removed = store
                .write()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .remove(key);
            empty(if removed.is_some() {
                StatusCode::NO_CONTENT
            } else {
                StatusCode::NOT_FOUND
            })
        }
        _ => empty(StatusCode::METHOD_NOT_ALLOWED),
    }
}

fn parse_port() -> Result<u16> {
    let arg = std::env::args().nth(1).context("usage: app <port>")?;
    arg.parse().with_context(|| format!("invalid port: {arg}"))
}

#[tokio::main]
async fn main() -> Result<()> {
    let port = parse_port()?;
    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = TcpListener::bind(addr)
        .await
        .with_context(|| format!("failed to bind {addr}"))?;
    let store = Store::default();

    loop {
        let (stream, _) = match listener.accept().await {
            Ok(conn) => conn,
            Err(err) => {
                eprintln!("accept failed: {err}");
                continue;
            }
        };
        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| handle(req, Arc::clone(&store)));
            if let Err(err) = http1::Builder::new()
                .serve_connection(TokioIo::new(stream), service)
                .await
            {
                eprintln!("connection error: {err}");
            }
        });
    }
}
