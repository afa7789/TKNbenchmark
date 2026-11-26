//! kvhttp: an in-memory HTTP/1.1 key-value server.

mod server;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use tokio::net::TcpSocket;

use crate::store::KvStore;

const BACKLOG: u32 = 1024;

fn parse_port(arg: Option<String>) -> Option<u16> {
    arg?.parse::<u16>().ok().filter(|&port| port != 0)
}

async fn run(port: u16) -> std::io::Result<()> {
    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let socket = TcpSocket::new_v4()?;
    socket.set_reuseaddr(true)?;
    socket.bind(addr)?;
    let listener = socket.listen(BACKLOG)?;
    let store = Arc::new(KvStore::new());

    tokio::select! {
        res = server::serve(listener, store) => res,
        () = shutdown_signal() => Ok(()),
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

fn main() -> ExitCode {
    let Some(port) = parse_port(std::env::args().nth(1)) else {
        eprintln!("usage: app <port>");
        return ExitCode::from(2);
    };
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(err) => {
            eprintln!("failed to start runtime: {err}");
            return ExitCode::FAILURE;
        }
    };
    match runtime.block_on(run(port)) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("server error: {err}");
            ExitCode::FAILURE
        }
    }
}
