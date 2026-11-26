//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: `app <port>` — listens on `127.0.0.1:<port>` until killed.

mod service;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

use crate::store::Store;

fn parse_port() -> Result<u16, String> {
    let mut args = std::env::args().skip(1);
    match (args.next(), args.next()) {
        (Some(port), None) => port.parse().map_err(|_| format!("invalid port: {port}")),
        _ => Err("usage: app <port>".to_owned()),
    }
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
        Err(err) => {
            eprintln!("failed to bind {addr}: {err}");
            return ExitCode::FAILURE;
        }
    };

    serve(listener, Arc::new(Store::new())).await
}

async fn serve(listener: TcpListener, store: Arc<Store>) -> ! {
    loop {
        let stream = match listener.accept().await {
            Ok((stream, _)) => stream,
            Err(err) => {
                // Typically transient (e.g. too many open files); keep serving.
                eprintln!("accept failed: {err}");
                tokio::task::yield_now().await;
                continue;
            }
        };
        let _ = stream.set_nodelay(true);

        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| service::handle(Arc::clone(&store), req));
            let result = http1::Builder::new()
                .serve_connection(TokioIo::new(stream), service)
                .await;
            if let Err(err) = result
                && !err.is_incomplete_message()
            {
                eprintln!("connection error: {err}");
            }
        });
    }
}
