//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: `app <port>` — listens on `127.0.0.1:<port>` until killed.

mod handler;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

use crate::store::Store;

fn parse_port() -> Option<u16> {
    let mut args = std::env::args().skip(1);
    let port = args.next()?.parse::<u16>().ok()?;
    (port != 0 && args.next().is_none()).then_some(port)
}

#[tokio::main]
async fn main() -> ExitCode {
    let Some(port) = parse_port() else {
        eprintln!("usage: app <port>");
        return ExitCode::from(2);
    };

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = match TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("failed to listen on {addr}: {err}");
            return ExitCode::FAILURE;
        }
    };

    let store = Arc::new(Store::default());

    tokio::select! {
        () = serve(listener, store) => ExitCode::FAILURE,
        () = shutdown_signal() => ExitCode::SUCCESS,
    }
}

/// Accepts connections forever, serving each on its own task.
async fn serve(listener: TcpListener, store: Arc<Store>) {
    loop {
        let stream = match listener.accept().await {
            Ok((stream, _)) => stream,
            Err(err) => {
                // Transient errors (e.g. EMFILE) should not bring the server down.
                eprintln!("accept failed: {err}");
                tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                continue;
            }
        };
        let _ = stream.set_nodelay(true);

        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| {
                let store = Arc::clone(&store);
                async move { handler::handle(&store, req).await }
            });
            if let Err(err) = http1::Builder::new()
                .keep_alive(false)
                .serve_connection(TokioIo::new(stream), service)
                .await
                && !err.is_incomplete_message()
            {
                eprintln!("connection error: {err}");
            }
        });
    }
}

async fn shutdown_signal() {
    use tokio::signal::unix::{SignalKind, signal};

    let mut term = signal(SignalKind::terminate()).expect("install SIGTERM handler");
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {}
        _ = term.recv() => {}
    }
}
