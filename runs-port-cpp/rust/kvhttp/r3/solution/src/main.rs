//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: `app <port>` — listens on 127.0.0.1:<port> and serves until killed.

mod http;
mod router;
mod store;

use std::io::{self, Read};
use std::net::{Ipv4Addr, Shutdown, TcpListener, TcpStream};
use std::process::ExitCode;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use crate::http::{HttpError, Response};
use crate::router::Router;
use crate::store::Store;

const IO_TIMEOUT: Duration = Duration::from_secs(30);
const DRAIN_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_DRAIN_BYTES: u64 = 64 * 1024 * 1024;

fn configure_client(stream: &TcpStream) -> io::Result<()> {
    stream.set_nodelay(true)?;
    stream.set_read_timeout(Some(IO_TIMEOUT))?;
    stream.set_write_timeout(Some(IO_TIMEOUT))
}

/// Discards unread request bytes (e.g. an oversized body we rejected) so that
/// closing does not trigger a RST that could clobber the reply.
fn drain(stream: &TcpStream) {
    if stream.set_read_timeout(Some(DRAIN_TIMEOUT)).is_ok() {
        let _ = io::copy(&mut stream.take(MAX_DRAIN_BYTES), &mut io::sink());
    }
}

fn serve_connection(stream: TcpStream, router: &Router) {
    if let Err(e) = configure_client(&stream) {
        eprintln!("kvhttp: configuring connection failed: {e}");
        return;
    }
    let response = match http::read_request(&stream) {
        Ok(Some(request)) => router.handle(request),
        Ok(None) => return,
        Err(HttpError(status)) => Response::status(status),
    };
    if response.write_to(&mut &stream).is_err() {
        return;
    }
    let _ = stream.shutdown(Shutdown::Write);
    drain(&stream);
}

fn parse_port(arg: &str) -> Option<u16> {
    if !arg.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    arg.parse().ok().filter(|&port| port != 0)
}

fn is_fd_exhaustion(e: &io::Error) -> bool {
    matches!(e.raw_os_error(), Some(libc::EMFILE | libc::ENFILE))
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    let [_, port_arg] = args.as_slice() else {
        let prog = args.first().map_or("app", String::as_str);
        eprintln!("usage: {prog} <port>");
        return ExitCode::from(2);
    };
    let Some(port) = parse_port(port_arg) else {
        eprintln!("kvhttp: invalid port '{port_arg}'");
        return ExitCode::from(2);
    };

    let listener = match TcpListener::bind((Ipv4Addr::LOCALHOST, port)) {
        Ok(listener) => listener,
        Err(e) => {
            eprintln!("kvhttp: bind: {e}");
            return ExitCode::FAILURE;
        }
    };

    let router = Arc::new(Router::new(Store::new()));

    for conn in listener.incoming() {
        let stream = match conn {
            Ok(stream) => stream,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::ConnectionAborted
                ) =>
            {
                continue;
            }
            Err(e) if is_fd_exhaustion(&e) => {
                thread::sleep(Duration::from_millis(10));
                continue;
            }
            Err(e) => {
                eprintln!("kvhttp: accept: {e}");
                return ExitCode::FAILURE;
            }
        };
        let router = Arc::clone(&router);
        if let Err(e) = thread::Builder::new()
            .name("kvhttp-conn".into())
            .spawn(move || serve_connection(stream, &router))
        {
            // Could not spawn a worker; drop this connection and keep serving.
            eprintln!("kvhttp: thread spawn failed: {e}");
        }
    }
    ExitCode::SUCCESS
}
