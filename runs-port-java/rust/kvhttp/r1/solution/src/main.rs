//! kvhttp: `app <port>` serves an in-memory key-value API on 127.0.0.1 until killed.

mod handler;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

use crate::store::KvStore;

#[tokio::main]
async fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let (Some(port_arg), None) = (args.next(), args.next()) else {
        eprintln!("usage: app <port>");
        return ExitCode::from(2);
    };
    let Ok(port) = port_arg.parse::<u16>() else {
        eprintln!("invalid port: {port_arg}");
        return ExitCode::from(2);
    };

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = match TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(e) => {
            eprintln!("failed to bind {addr}: {e}");
            return ExitCode::FAILURE;
        }
    };

    serve(listener, Arc::new(KvStore::new())).await
}

async fn serve(listener: TcpListener, store: Arc<KvStore>) -> ! {
    loop {
        let stream = match listener.accept().await {
            Ok((stream, _)) => stream,
            Err(e) => {
                // Typically resource exhaustion (e.g. EMFILE); back off briefly and retry.
                eprintln!("accept failed: {e}");
                tokio::time::sleep(Duration::from_millis(10)).await;
                continue;
            }
        };
        let _ = stream.set_nodelay(true);

        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |request| handler::handle(Arc::clone(&store), request));
            if let Err(e) = http1::Builder::new()
                .serve_connection(TokioIo::new(stream), service)
                .await
            {
                eprintln!("connection error: {e}");
            }
        });
    }
}
