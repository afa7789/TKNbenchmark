//! kvhttp: an in-memory HTTP/1.1 key-value server.

mod http;
mod routes;
mod server;
mod store;

use std::process::ExitCode;

use server::{Server, ServerOptions};
use store::KvStore;

fn parse_port(arg: &str) -> Option<u16> {
    if arg.is_empty() || !arg.bytes().all(|c| c.is_ascii_digit()) {
        return None;
    }
    arg.parse().ok().filter(|&port| port != 0)
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    let [_, port_arg] = args.as_slice() else {
        let program = args.first().map_or("app", String::as_str);
        eprintln!("usage: {program} <port>");
        return ExitCode::from(2);
    };
    let Some(port) = parse_port(port_arg) else {
        eprintln!("invalid port: {port_arg}");
        return ExitCode::from(2);
    };

    let store = KvStore::new();
    let options = ServerOptions {
        port,
        ..ServerOptions::default()
    };
    match Server::bind(options, move |request| routes::route(&store, request)) {
        Ok(server) => server.run(),
        Err(e) => {
            eprintln!("fatal: bind: {e}");
            ExitCode::FAILURE
        }
    }
}
