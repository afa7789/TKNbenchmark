//! kvhttp: a minimal in-memory HTTP/1.1 key-value server (see SPEC.md).

mod app;
mod store;

use std::convert::Infallible;
use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use bytes::{Bytes, BytesMut};
use http_body_util::BodyExt;
use hyper::body::Incoming;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

use crate::app::{Body, MAX_VALUE_SIZE};
use crate::store::Store;

/// Why a request body could not be read.
enum BodyError {
    TooLarge,
    Malformed,
}

/// Reads the whole request body, refusing anything over [`MAX_VALUE_SIZE`].
///
/// An oversized body is still drained so the client reliably receives the
/// error response instead of a connection reset.
async fn read_body(mut body: Incoming) -> Result<Bytes, BodyError> {
    let mut buf = BytesMut::new();
    let mut too_large = false;
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|_| BodyError::Malformed)?;
        let Ok(data) = frame.into_data() else {
            continue;
        };
        if too_large || buf.len() + data.len() > MAX_VALUE_SIZE {
            too_large = true;
            buf.clear();
        } else {
            buf.extend_from_slice(&data);
        }
    }
    if too_large {
        Err(BodyError::TooLarge)
    } else {
        Ok(buf.freeze())
    }
}

async fn serve(store: Arc<Store>, req: Request<Incoming>) -> Result<Response<Body>, Infallible> {
    let (parts, body) = req.into_parts();
    let res = match read_body(body).await {
        Ok(body) => app::handle(&store, &parts.method, parts.uri.path(), body),
        Err(BodyError::TooLarge) => app::empty(StatusCode::PAYLOAD_TOO_LARGE),
        Err(BodyError::Malformed) => app::empty(StatusCode::BAD_REQUEST),
    };
    Ok(res)
}

async fn run(port: u16) -> std::io::Result<()> {
    let listener = TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, port))).await?;
    let store = Arc::new(Store::new());
    loop {
        let (stream, _) = match listener.accept().await {
            Ok(conn) => conn,
            Err(err) => {
                // Transient failures such as running out of file descriptors
                // must not bring the server down.
                eprintln!("kvhttp: accept failed: {err}");
                continue;
            }
        };
        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| serve(Arc::clone(&store), req));
            // Client disconnects and protocol errors only affect this connection.
            let _ = http1::Builder::new()
                .keep_alive(false)
                .serve_connection(TokioIo::new(stream), service)
                .await;
        });
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    let mut args = std::env::args();
    let prog = args.next().unwrap_or_else(|| "kvhttp".into());
    let port = match (args.next().map(|p| p.parse::<u16>()), args.next()) {
        (Some(Ok(port)), None) => port,
        _ => {
            eprintln!("usage: {prog} <port>");
            return ExitCode::from(2);
        }
    };
    match run(port).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("kvhttp: {err}");
            ExitCode::FAILURE
        }
    }
}
