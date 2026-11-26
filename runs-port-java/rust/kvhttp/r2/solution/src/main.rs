//! Entry point: `app <port>` serves the key-value API on 127.0.0.1.

mod handler;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

use crate::store::KvStore;

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let (Some(port), None) = (args.next(), args.next()) else {
        eprintln!("usage: app <port>");
        return ExitCode::from(2);
    };
    let Ok(port) = port.parse::<u16>() else {
        eprintln!("invalid port: {port}");
        return ExitCode::from(2);
    };

    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(err) => {
            eprintln!("failed to start runtime: {err}");
            return ExitCode::FAILURE;
        }
    };
    match runtime.block_on(serve(SocketAddr::from((Ipv4Addr::LOCALHOST, port)))) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("server error: {err}");
            ExitCode::FAILURE
        }
    }
}

async fn serve(addr: SocketAddr) -> std::io::Result<()> {
    let listener = TcpListener::bind(addr).await?;
    let store = Arc::new(KvStore::new());

    loop {
        let (stream, _) = match listener.accept().await {
            Ok(conn) => conn,
            Err(err) => {
                // Transient failures (e.g. too many open files) must not stop the server.
                eprintln!("accept failed: {err}");
                tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                continue;
            }
        };
        let store = Arc::clone(&store);
        tokio::spawn(async move {
            let service = service_fn(move |req| handler::handle(Arc::clone(&store), req));
            if let Err(err) = http1::Builder::new()
                .serve_connection(TokioIo::new(stream), service)
                .await
            {
                eprintln!("connection error: {err}");
            }
        });
    }
}
