//! kvhttp: a small in-memory HTTP/1.1 key-value server.
//!
//! One request is handled per connection; every response carries an exact
//! `Content-Length` and the connection is closed afterwards.

mod app;
mod http;

use std::net::IpAddr;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use clap::Parser;
use tokio::io::{AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};

use crate::app::App;
use crate::http::{ReadError, Response};

const READ_TIMEOUT: Duration = Duration::from_secs(30);

/// In-memory HTTP key-value server.
#[derive(Debug, Parser)]
#[command(name = "kvhttp")]
struct Args {
    /// TCP port to listen on.
    port: u16,
    /// Address to bind.
    #[arg(long, default_value = "127.0.0.1")]
    host: IpAddr,
}

async fn handle_connection(app: &App, stream: TcpStream) {
    let mut stream = BufReader::new(stream);
    let response = match tokio::time::timeout(READ_TIMEOUT, http::read_request(&mut stream)).await {
        Ok(Ok(request)) => app.handle(request),
        Ok(Err(ReadError::Http(status))) => Response::new(status),
        // Peer vanished, socket failed or the client was too slow: nothing to send.
        Ok(Err(ReadError::Disconnected)) | Err(_) => return,
    };

    let stream = stream.get_mut();
    let result = async {
        stream.write_all(&response.encode_head()).await?;
        stream.write_all(&response.body).await?;
        stream.shutdown().await
    }
    .await;
    if let Err(err) = result {
        // Clients disconnecting mid-response are routine; just note it.
        if !matches!(
            err.kind(),
            std::io::ErrorKind::BrokenPipe
                | std::io::ErrorKind::ConnectionReset
                | std::io::ErrorKind::NotConnected
        ) {
            eprintln!("kvhttp: error writing response: {err}");
        }
    }
}

async fn serve(args: Args) -> std::io::Result<()> {
    let listener = TcpListener::bind((args.host, args.port)).await?;
    let app = Arc::new(App::default());
    loop {
        let (stream, _) = match listener.accept().await {
            Ok(conn) => conn,
            Err(err) => {
                // Usually transient (e.g. out of file descriptors); back off briefly.
                eprintln!("kvhttp: accept failed: {err}");
                tokio::time::sleep(Duration::from_millis(10)).await;
                continue;
            }
        };
        let app = Arc::clone(&app);
        tokio::spawn(async move { handle_connection(&app, stream).await });
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    let args = Args::parse();
    let addr = (args.host, args.port);
    match serve(args).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("kvhttp: cannot serve on {}:{}: {err}", addr.0, addr.1);
            ExitCode::FAILURE
        }
    }
}
