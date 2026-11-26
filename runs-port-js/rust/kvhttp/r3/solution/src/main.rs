//! `kvhttp <port>`: an in-memory HTTP/1.1 key-value server on 127.0.0.1.

mod server;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;

use tokio::net::TcpListener;

fn parse_port() -> Option<u16> {
    let mut args = std::env::args().skip(1);
    let port = args.next()?.parse::<u16>().ok().filter(|&p| p != 0)?;
    args.next().is_none().then_some(port)
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
            eprintln!("kvhttp: cannot listen on {addr}: {err}");
            return ExitCode::FAILURE;
        }
    };

    tokio::select! {
        () = server::serve(listener, server::Store::default()) => ExitCode::FAILURE,
        () = shutdown_signal() => ExitCode::SUCCESS,
    }
}

/// Resolves on SIGINT or SIGTERM.
async fn shutdown_signal() {
    use tokio::signal::unix::{SignalKind, signal};

    let mut term = signal(SignalKind::terminate()).expect("install SIGTERM handler");
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {}
        _ = term.recv() => {}
    }
}
