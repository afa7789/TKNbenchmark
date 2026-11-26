//! kvhttp: a minimal HTTP/1.1 in-memory key-value server.
//!
//! One thread per connection, one request per connection. The store is
//! guarded by a reader-writer lock (see `store`).

mod http;
mod server;
mod store;

use std::net::{Ipv4Addr, TcpListener};
use std::process::ExitCode;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use crate::store::Store;

/// Pause after a failed `accept` (typically resource exhaustion).
const ACCEPT_BACKOFF: Duration = Duration::from_millis(10);

fn parse_port(s: &str) -> Option<u16> {
    s.parse().ok().filter(|&p| p != 0)
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    let [_, port_arg] = args.as_slice() else {
        let prog = args.first().map_or("kvhttp", String::as_str);
        eprintln!("usage: {prog} <port>");
        return ExitCode::from(2);
    };
    let Some(port) = parse_port(port_arg) else {
        eprintln!("invalid port: {port_arg}");
        return ExitCode::from(2);
    };

    let listener = match TcpListener::bind((Ipv4Addr::LOCALHOST, port)) {
        Ok(listener) => listener,
        Err(e) => {
            eprintln!("bind 127.0.0.1:{port}: {e}");
            return ExitCode::FAILURE;
        }
    };

    let store = Arc::new(Store::new());
    loop {
        let stream = match listener.accept() {
            Ok((stream, _)) => stream,
            Err(e) => {
                eprintln!("accept: {e}");
                thread::sleep(ACCEPT_BACKOFF);
                continue;
            }
        };

        let store = Arc::clone(&store);
        // On failure the closure, and with it the stream, is dropped, which
        // closes the connection.
        if let Err(e) = thread::Builder::new()
            .name("conn".into())
            .spawn(move || server::handle_connection(&store, stream))
        {
            eprintln!("spawn: {e}");
        }
    }
}
