//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: `app <port>` — listens on `127.0.0.1:<port>` until killed.

mod app;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;

use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

use crate::app::App;

#[tokio::main]
async fn main() -> ExitCode {
    let Some(port) = parse_port(std::env::args().nth(1).as_deref()) else {
        eprintln!("usage: app <port>");
        return ExitCode::from(2);
    };
    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = match TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("cannot listen on {addr}: {err}");
            return ExitCode::FAILURE;
        }
    };

    tokio::select! {
        () = serve(listener, App::new()) => ExitCode::SUCCESS,
        () = shutdown_signal() => ExitCode::SUCCESS,
    }
}

fn parse_port(arg: Option<&str>) -> Option<u16> {
    arg?.parse::<u16>().ok().filter(|&p| p != 0)
}

async fn serve(listener: TcpListener, app: App) {
    loop {
        let (stream, _) = match listener.accept().await {
            Ok(conn) => conn,
            Err(err) => {
                // Transient (e.g. too many open files); keep serving.
                eprintln!("accept failed: {err}");
                tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                continue;
            }
        };
        let _ = stream.set_nodelay(true);
        let app = app.clone();
        tokio::spawn(async move {
            let service = service_fn(move |req| {
                let app = app.clone();
                async move { Ok::<_, std::convert::Infallible>(app.handle(req).await) }
            });
            // Client disconnects and malformed requests are routine; nothing to report.
            let _ = http1::Builder::new()
                .serve_connection(TokioIo::new(stream), service)
                .await;
        });
    }
}

async fn shutdown_signal() {
    let ctrl_c = tokio::signal::ctrl_c();
    #[cfg(unix)]
    {
        use tokio::signal::unix::{SignalKind, signal};
        match signal(SignalKind::terminate()) {
            Ok(mut term) => tokio::select! {
                _ = ctrl_c => {},
                _ = term.recv() => {},
            },
            Err(_) => {
                let _ = ctrl_c.await;
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = ctrl_c.await;
    }
}
