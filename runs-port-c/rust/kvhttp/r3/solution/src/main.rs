//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: `app <port>` — listens on `127.0.0.1:<port>` until killed.

mod routes;
mod server;
mod store;

use std::process::ExitCode;

fn parse_port(arg: &str) -> Option<u16> {
    arg.parse().ok().filter(|&port| port != 0)
}

#[tokio::main]
async fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    let port = match args.as_slice() {
        [_, port] => parse_port(port),
        _ => None,
    };
    let Some(port) = port else {
        let program = args.first().map_or("app", String::as_str);
        eprintln!("usage: {program} <port>");
        return ExitCode::from(2);
    };

    match server::run(port).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("error: {err}");
            ExitCode::FAILURE
        }
    }
}
