//! Accept loop and per-connection HTTP/1.1 handling.

use std::io;
use std::net::{Ipv4Addr, SocketAddr};
use std::sync::Arc;
use std::time::Duration;

use bytes::{Bytes, BytesMut};
use http_body_util::{BodyExt, Full};
use hyper::body::Incoming;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::{TokioIo, TokioTimer};
use tokio::net::{TcpListener, TcpStream};

use crate::routes::{self, MAX_VALUE_LEN};
use crate::store::Store;

/// Overall budget for one connection (receiving the request and sending the reply).
const CONNECTION_TIMEOUT: Duration = Duration::from_secs(30);
/// How long a client may take to send the request head.
const HEADER_READ_TIMEOUT: Duration = Duration::from_secs(10);
/// Oversized bodies are read and discarded up to this many bytes before the
/// 413 is sent, so that closing the socket does not reset the connection and
/// destroy the response before the client reads it.
const MAX_DRAIN_LEN: usize = 16 * MAX_VALUE_LEN;
/// Pause after a failed `accept` (e.g. out of file descriptors) to avoid spinning.
const ACCEPT_BACKOFF: Duration = Duration::from_millis(50);

/// Binds `127.0.0.1:port` and serves until the process is killed.
pub async fn run(port: u16) -> io::Result<()> {
    let listener = TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, port))).await?;
    let store = Arc::new(Store::new());

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                tokio::spawn(serve(stream, Arc::clone(&store)));
            }
            Err(err) => {
                eprintln!("accept: {err}");
                tokio::time::sleep(ACCEPT_BACKOFF).await;
            }
        }
    }
}

async fn serve(stream: TcpStream, store: Arc<Store>) {
    // Best effort: a failure only affects latency.
    let _ = stream.set_nodelay(true);

    let service = service_fn(move |request| handle(Arc::clone(&store), request));
    let connection = http1::Builder::new()
        .timer(TokioTimer::new())
        .header_read_timeout(HEADER_READ_TIMEOUT)
        .serve_connection(TokioIo::new(stream), service);

    // Errors here are per-connection (client went away, malformed request,
    // timeout) and need no action beyond dropping the connection.
    let _ = tokio::time::timeout(CONNECTION_TIMEOUT, connection).await;
}

async fn handle(
    store: Arc<Store>,
    request: Request<Incoming>,
) -> Result<Response<Full<Bytes>>, hyper::Error> {
    let (parts, body) = request.into_parts();
    let response = match read_body(body).await? {
        Some(body) => routes::handle(&store, &parts.method, parts.uri.path(), body),
        None => routes::status(StatusCode::PAYLOAD_TOO_LARGE),
    };
    Ok(response)
}

/// Collects the request body, or returns `None` if it exceeds `MAX_VALUE_LEN`.
async fn read_body(mut body: Incoming) -> Result<Option<Bytes>, hyper::Error> {
    let mut buf = BytesMut::new();
    let mut received = 0usize;
    while let Some(frame) = body.frame().await {
        let Ok(data) = frame?.into_data() else {
            continue; // trailers carry nothing we use
        };
        received = received.saturating_add(data.len());
        if received <= MAX_VALUE_LEN {
            buf.extend_from_slice(&data);
        } else if received > MAX_DRAIN_LEN {
            break;
        }
    }
    Ok((received <= MAX_VALUE_LEN).then(|| buf.freeze()))
}
