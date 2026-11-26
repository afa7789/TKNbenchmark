//! kvhttp: an in-memory HTTP/1.1 key-value server.

mod http;
mod router;
mod store;

use std::io;
use std::net::{Ipv4Addr, Shutdown, TcpListener, TcpStream};
use std::panic::{self, AssertUnwindSafe};
use std::process::ExitCode;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use http::{Limits, ReadOutcome, Response, StatusCode};
use router::Router;
use store::KvStore;

/// Don't let an idle or stalled client pin a thread forever.
const IO_TIMEOUT: Duration = Duration::from_secs(30);

fn configure_client(stream: &TcpStream) -> io::Result<()> {
    stream.set_nodelay(true)?;
    stream.set_read_timeout(Some(IO_TIMEOUT))?;
    stream.set_write_timeout(Some(IO_TIMEOUT))
}

fn serve_connection(mut stream: TcpStream, store: &KvStore) {
    if let Err(e) = configure_client(&stream) {
        eprintln!("failed to configure connection: {e}");
        return;
    }

    let response = match http::read_request(&mut stream, &Limits::default()) {
        ReadOutcome::Request(request) => {
            let router = Router::new(store);
            panic::catch_unwind(AssertUnwindSafe(|| router.handle(request)))
                .unwrap_or_else(|_| Response::empty(StatusCode::InternalServerError))
        }
        ReadOutcome::Reject(response) => response,
        ReadOutcome::Disconnected => return,
    };
    // Write failures mean the peer went away; nothing left to do.
    if response.write_to(&mut stream).is_ok() {
        // Half-close so the client reads the full response before the FIN.
        let _ = stream.shutdown(Shutdown::Write);
    }
}

fn is_transient_accept_error(e: &io::Error) -> bool {
    matches!(
        e.kind(),
        io::ErrorKind::Interrupted | io::ErrorKind::ConnectionAborted
    )
}

fn is_fd_exhaustion(e: &io::Error) -> bool {
    matches!(e.raw_os_error(), Some(code) if code == 23 || code == 24) // ENFILE, EMFILE
}

fn run(port: u16) -> io::Result<()> {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, port))?;
    let store = Arc::new(KvStore::new());

    loop {
        let stream = match listener.accept() {
            Ok((stream, _)) => stream,
            Err(e) if is_transient_accept_error(&e) => continue,
            Err(e) if is_fd_exhaustion(&e) => {
                thread::sleep(Duration::from_millis(10));
                continue;
            }
            Err(e) => return Err(e),
        };
        // One thread per connection: connections are short-lived and the
        // required concurrency is modest.
        let store = Arc::clone(&store);
        if let Err(e) = thread::Builder::new()
            .name("conn".into())
            .spawn(move || serve_connection(stream, &store))
        {
            eprintln!("failed to spawn handler: {e}");
        }
    }
}

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

    match run(port) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("fatal: {e}");
            ExitCode::FAILURE
        }
    }
}
