//! kvhttp: an in-memory HTTP/1.1 key-value server.

mod handler;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use tokio::net::TcpListener;

use crate::store::Store;

fn parse_port() -> Option<u16> {
    let mut args = std::env::args().skip(1);
    let port = args.next()?.parse::<u16>().ok()?;
    (args.next().is_none() && port != 0).then_some(port)
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
            eprintln!("failed to bind {addr}: {err}");
            return ExitCode::FAILURE;
        }
    };

    let app = handler::router(Arc::new(Store::new()));
    if let Err(err) = axum::serve(listener, app).await {
        eprintln!("server error: {err}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
