//! kvhttp: an HTTP/1.1 in-memory key-value server.
//!
//! Usage: `kvhttp <port>` (listens on 127.0.0.1).

mod routes;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::{TokioIo, TokioTimer};
use tokio::net::TcpListener;

use crate::store::Store;

/// How long a client may take to send the request head.
const HEADER_TIMEOUT: Duration = Duration::from_secs(30);
/// Back-off after a resource-exhaustion accept failure (e.g. EMFILE).
const ACCEPT_BACKOFF: Duration = Duration::from_millis(10);

fn parse_port(arg: &str) -> Option<u16> {
    arg.parse().ok().filter(|&port| port != 0)
}

#[tokio::main]
async fn main() -> ExitCode {
    let mut args = std::env::args();
    let program = args.next().unwrap_or_else(|| "kvhttp".into());
    let port = match (args.next().as_deref().and_then(parse_port), args.next()) {
        (Some(port), None) => port,
        _ => {
            eprintln!("usage: {program} <port>");
            return ExitCode::from(2);
        }
    };

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = match TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("bind {addr}: {err}");
            return ExitCode::FAILURE;
        }
    };
    serve(listener, Arc::new(Store::new())).await;
    ExitCode::FAILURE
}

/// Accepts connections forever, serving each on its own task.
async fn serve(listener: TcpListener, store: Arc<Store>) {
    loop {
        let stream = match listener.accept().await {
            Ok((stream, _)) => stream,
            Err(err) => {
                // Transient failures (aborted handshakes, fd exhaustion) must
                // not take the server down; pause briefly to avoid spinning.
                eprintln!("accept: {err}");
                tokio::time::sleep(ACCEPT_BACKOFF).await;
                continue;
            }
        };
        if let Err(err) = stream.set_nodelay(true) {
            eprintln!("set_nodelay: {err}");
        }
        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| routes::handle(Arc::clone(&store), req));
            // Errors here are clients that disconnected or sent garbage;
            // hyper has already answered whatever could be answered.
            let _ = http1::Builder::new()
                .timer(TokioTimer::new())
                // Clients may shut down their write side after sending the
                // request; still answer it.
                .half_close(true)
                .header_read_timeout(HEADER_TIMEOUT)
                .serve_connection(TokioIo::new(stream), service)
                .await;
        });
    }
}

#[cfg(test)]
mod tests {
    use super::parse_port;

    #[test]
    fn ports() {
        assert_eq!(parse_port("8080"), Some(8080));
        assert_eq!(parse_port("65535"), Some(65535));
        assert_eq!(parse_port("0"), None);
        assert_eq!(parse_port("65536"), None);
        assert_eq!(parse_port("-1"), None);
        assert_eq!(parse_port("80x"), None);
        assert_eq!(parse_port(""), None);
    }
}
