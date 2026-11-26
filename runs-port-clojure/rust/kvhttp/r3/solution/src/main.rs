//! `app <port>` serves the kvhttp API on 127.0.0.1:<port>.

mod handler;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use axum::Router;
use axum::extract::DefaultBodyLimit;

use crate::store::Store;

fn parse_port(arg: Option<String>) -> Option<u16> {
    arg?.parse().ok().filter(|&port| port != 0)
}

#[tokio::main]
async fn main() -> ExitCode {
    let Some(port) = parse_port(std::env::args().nth(1)) else {
        eprintln!("usage: app <port>");
        return ExitCode::from(2);
    };

    let app = Router::new()
        .fallback(handler::handle)
        .layer(DefaultBodyLimit::max(handler::MAX_BODY_BYTES))
        .with_state(Arc::new(Store::new()));

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("failed to bind {addr}: {err}");
            return ExitCode::FAILURE;
        }
    };

    if let Err(err) = axum::serve(listener, app).await {
        eprintln!("server error: {err}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
