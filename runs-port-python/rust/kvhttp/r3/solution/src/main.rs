//! kvhttp: a minimal in-memory HTTP/1.1 key-value server.
//!
//! Usage: `app <port>` — listens on `127.0.0.1:<port>` until killed.

mod app;
mod http;
mod server;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;

use app::App;
use server::Server;
use store::Store;

fn parse_port(args: &[String]) -> Option<u16> {
    match args {
        [port] if !port.is_empty() && port.bytes().all(|b| b.is_ascii_digit()) => {
            port.parse::<u16>().ok().filter(|&p| p != 0)
        }
        _ => None,
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(port) = parse_port(&args) else {
        eprintln!("usage: app <port>");
        return ExitCode::from(2);
    };

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    match Server::new(App::new(Store::new())).serve(addr).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: cannot listen on {addr}: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::parse_port;

    fn p(args: &[&str]) -> Option<u16> {
        parse_port(&args.iter().map(|s| s.to_string()).collect::<Vec<_>>())
    }

    #[test]
    fn port_validation() {
        assert_eq!(p(&["8080"]), Some(8080));
        assert_eq!(p(&["65535"]), Some(65535));
        for bad in [
            &[][..],
            &["0"],
            &["65536"],
            &["+80"],
            &["-1"],
            &[""],
            &["80", "81"],
        ] {
            assert_eq!(p(bad), None, "{bad:?}");
        }
    }
}
