//! kvhttp: an in-memory HTTP/1.1 key-value server.

mod server;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

use crate::store::KvStore;

fn parse_port(raw: Option<String>) -> Option<u16> {
    raw?.parse().ok().filter(|&port| port != 0)
}

#[tokio::main]
async fn main() -> ExitCode {
    let Some(port) = parse_port(std::env::args().nth(1)) else {
        eprintln!("usage: app <port>");
        return ExitCode::from(2);
    };

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = match TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("server error: {err}");
            return ExitCode::FAILURE;
        }
    };
    eprintln!("kvhttp listening on {addr}");

    tokio::select! {
        () = serve(listener, Arc::new(KvStore::new())) => ExitCode::FAILURE,
        () = shutdown_signal() => ExitCode::SUCCESS,
    }
}

/// Accepts connections forever, serving each on its own task.
async fn serve(listener: TcpListener, store: Arc<KvStore>) {
    loop {
        let stream = match listener.accept().await {
            Ok((stream, _)) => stream,
            Err(err) => {
                // Transient failures (e.g. EMFILE) must not bring the server down.
                eprintln!("accept error: {err}");
                tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                continue;
            }
        };
        let _ = stream.set_nodelay(true);
        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| server::handle(Arc::clone(&store), req));
            if let Err(err) = http1::Builder::new()
                .serve_connection(TokioIo::new(stream), service)
                .await
            {
                eprintln!("connection error: {err}");
            }
        });
    }
}

async fn shutdown_signal() {
    use tokio::signal::unix::{SignalKind, signal};
    let (Ok(mut term), Ok(mut int)) = (
        signal(SignalKind::terminate()),
        signal(SignalKind::interrupt()),
    ) else {
        return std::future::pending().await;
    };
    tokio::select! {
        _ = term.recv() => {}
        _ = int.recv() => {}
    }
}
