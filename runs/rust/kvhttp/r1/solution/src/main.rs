//! kvhttp: a minimal in-memory HTTP/1.1 key-value server.

mod routes;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

use crate::routes::Store;

fn parse_port() -> Result<u16, String> {
    let mut args = std::env::args().skip(1);
    let (Some(arg), None) = (args.next(), args.next()) else {
        return Err("usage: app <port>".to_owned());
    };
    arg.parse().map_err(|e| format!("invalid port {arg:?}: {e}"))
}

#[tokio::main]
async fn main() -> ExitCode {
    let port = match parse_port() {
        Ok(port) => port,
        Err(msg) => {
            eprintln!("{msg}");
            return ExitCode::from(2);
        }
    };

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = match TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(e) => {
            eprintln!("failed to bind {addr}: {e}");
            return ExitCode::FAILURE;
        }
    };

    let store = Arc::new(Store::default());
    loop {
        let stream = match listener.accept().await {
            Ok((stream, _)) => stream,
            Err(e) => {
                // Transient errors (e.g. EMFILE) must not bring the server down.
                eprintln!("accept failed: {e}");
                tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                continue;
            }
        };
        let _ = stream.set_nodelay(true);
        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| routes::handle(Arc::clone(&store), req));
            if let Err(e) = http1::Builder::new()
                .serve_connection(TokioIo::new(stream), service)
                .await
            {
                eprintln!("connection error: {e}");
            }
        });
    }
}
