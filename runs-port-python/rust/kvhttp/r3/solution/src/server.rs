//! TCP accept loop and per-connection request handling.

use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use tokio::io::AsyncWriteExt;
use tokio::net::{TcpSocket, TcpStream};

use crate::app::App;
use crate::http::{ReadError, Response, StreamReader};

/// How long a client may take to send a complete request.
const READ_TIMEOUT: Duration = Duration::from_secs(30);
const LISTEN_BACKLOG: u32 = 1024;

pub struct Server {
    app: Arc<App>,
}

impl Server {
    pub fn new(app: App) -> Self {
        Self { app: Arc::new(app) }
    }

    /// Serves forever on `addr`. Returns only if binding fails.
    pub async fn serve(self, addr: SocketAddr) -> io::Result<()> {
        let socket = if addr.is_ipv4() {
            TcpSocket::new_v4()?
        } else {
            TcpSocket::new_v6()?
        };
        socket.set_reuseaddr(true)?;
        socket.bind(addr)?;
        let listener = socket.listen(LISTEN_BACKLOG)?;

        loop {
            match listener.accept().await {
                Ok((stream, _)) => {
                    let app = Arc::clone(&self.app);
                    tokio::spawn(async move {
                        if let Err(e) = handle_connection(&app, stream).await {
                            eprintln!("warning: error while serving request: {e}");
                        }
                    });
                }
                Err(e) => {
                    // Typically resource exhaustion (e.g. EMFILE); back off briefly.
                    eprintln!("warning: accept failed: {e}");
                    tokio::time::sleep(Duration::from_millis(50)).await;
                }
            }
        }
    }
}

/// Reads one request, writes one response, then closes the connection.
async fn handle_connection(app: &App, mut stream: TcpStream) -> io::Result<()> {
    let mut reader = StreamReader::new(&mut stream);
    let response = match tokio::time::timeout(READ_TIMEOUT, reader.read_request()).await {
        Ok(Ok(request)) => app.handle(request),
        Ok(Err(ReadError::Http(status))) => Response::empty(status),
        // The client went away or stalled; nothing useful to send.
        Ok(Err(ReadError::Io(_))) | Err(_) => return Ok(()),
    };

    let result = write_response(&mut stream, &response).await;
    match result {
        Err(e) if is_disconnect(&e) => Ok(()),
        other => other,
    }
}

async fn write_response(stream: &mut TcpStream, response: &Response) -> io::Result<()> {
    stream.write_all(&response.encode_head()).await?;
    stream.write_all(&response.body).await?;
    stream.shutdown().await
}

fn is_disconnect(e: &io::Error) -> bool {
    matches!(
        e.kind(),
        io::ErrorKind::BrokenPipe
            | io::ErrorKind::ConnectionReset
            | io::ErrorKind::ConnectionAborted
            | io::ErrorKind::NotConnected
    )
}
