//! Minimal HTTP/1.1 server: one request per connection, one thread per
//! connection.

use std::io::{self, ErrorKind, Read, Write};
use std::net::{Ipv4Addr, Shutdown, SocketAddr, TcpListener, TcpStream};
use std::panic::{self, AssertUnwindSafe};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use crate::http::{self, HeadError, Request, Response};

#[derive(Debug, Clone)]
pub struct ServerOptions {
    pub port: u16,
    pub max_head_bytes: usize,
    pub max_body_bytes: usize,
    pub io_timeout: Duration,
}

impl Default for ServerOptions {
    fn default() -> Self {
        Self {
            port: 8080,
            max_head_bytes: 64 * 1024,
            max_body_bytes: 1024 * 1024,
            io_timeout: Duration::from_secs(10),
        }
    }
}

/// Why reading a request failed.
#[derive(Debug)]
enum ReadError {
    /// The peer misbehaved in a way that should produce this HTTP status.
    Http(u16),
    /// The connection is unusable (peer closed, I/O error).
    Closed,
}

type ReadResult<T> = Result<T, ReadError>;

const READ_CHUNK: usize = 64 * 1024;
const MAX_DRAIN_BYTES: usize = 16 * 1024 * 1024;
const LINGER_TIMEOUT: Duration = Duration::from_secs(1);
const ACCEPT_BACKOFF: Duration = Duration::from_millis(10);

struct Connection<'a> {
    stream: TcpStream,
    options: &'a ServerOptions,
    buffer: Vec<u8>,
}

impl<'a> Connection<'a> {
    fn new(stream: TcpStream, options: &'a ServerOptions) -> Self {
        Self {
            stream,
            options,
            buffer: Vec::new(),
        }
    }

    fn read_request(&mut self) -> ReadResult<Request> {
        let head = loop {
            match http::parse_head(&self.buffer) {
                Ok(head) => break head,
                Err(HeadError::Malformed) => return Err(ReadError::Http(400)),
                Err(HeadError::Incomplete) => {
                    if self.buffer.len() > self.options.max_head_bytes {
                        return Err(ReadError::Http(431));
                    }
                    if !self.fill()? {
                        return Err(ReadError::Closed);
                    }
                }
            }
        };
        self.buffer.drain(..head.head_size);
        let mut request = head.request;
        request.body = self.read_body(&request)?;
        Ok(request)
    }

    fn send_response(&mut self, response: &Response, include_body: bool) -> io::Result<()> {
        self.stream.write_all(&response.serialize_head())?;
        if include_body {
            self.stream.write_all(&response.body)?;
        }
        self.stream.flush()
    }

    /// Half-closes the socket and discards any remaining input so the client
    /// sees the response rather than a reset.
    fn linger_close(&mut self) {
        let _ = self.stream.shutdown(Shutdown::Write);
        let _ = self.stream.set_read_timeout(Some(LINGER_TIMEOUT));
        let mut scratch = [0u8; 16 * 1024];
        let mut drained = 0;
        while drained < MAX_DRAIN_BYTES {
            match self.stream.read(&mut scratch) {
                Ok(0) => break,
                Ok(n) => drained += n,
                Err(e) if e.kind() == ErrorKind::Interrupted => {}
                Err(_) => break,
            }
        }
    }

    /// Reads more bytes into the buffer; returns `false` on EOF.
    fn fill(&mut self) -> ReadResult<bool> {
        let start = self.buffer.len();
        self.buffer.resize(start + READ_CHUNK, 0);
        let result = loop {
            match self.stream.read(&mut self.buffer[start..]) {
                Err(e) if e.kind() == ErrorKind::Interrupted => {}
                other => break other,
            }
        };
        self.buffer.truncate(start + *result.as_ref().unwrap_or(&0));
        match result {
            Ok(n) => Ok(n > 0),
            Err(e) => match e.kind() {
                ErrorKind::WouldBlock | ErrorKind::TimedOut => Err(ReadError::Http(408)),
                _ => Err(ReadError::Closed),
            },
        }
    }

    /// Ensures at least `n` bytes are buffered.
    fn require(&mut self, n: usize) -> ReadResult<()> {
        while self.buffer.len() < n {
            if !self.fill()? {
                return Err(ReadError::Http(400));
            }
        }
        Ok(())
    }

    fn take(&mut self, n: usize) -> ReadResult<Vec<u8>> {
        self.require(n)?;
        let rest = self.buffer.split_off(n);
        Ok(std::mem::replace(&mut self.buffer, rest))
    }

    fn read_line(&mut self) -> ReadResult<Vec<u8>> {
        loop {
            if let Some(pos) = http::find(&self.buffer, b"\r\n") {
                let mut line = self.take(pos + 2)?;
                line.truncate(pos);
                return Ok(line);
            }
            if self.buffer.len() > self.options.max_head_bytes || !self.fill()? {
                return Err(ReadError::Http(400));
            }
        }
    }

    fn read_body(&mut self, request: &Request) -> ReadResult<Vec<u8>> {
        if let Some(te) = request.header("Transfer-Encoding") {
            if !te.eq_ignore_ascii_case("chunked") {
                return Err(ReadError::Http(501));
            }
            return self.read_chunked_body();
        }
        let Some(length) = request.header("Content-Length") else {
            return Ok(Vec::new());
        };
        let length = parse_content_length(length)?;
        if length > self.options.max_body_bytes {
            return Err(ReadError::Http(413));
        }
        self.take(length)
    }

    fn read_chunked_body(&mut self) -> ReadResult<Vec<u8>> {
        let mut body = Vec::new();
        loop {
            let line = self.read_line()?;
            let size_text = line.split(|&c| c == b';').next().unwrap_or_default();
            let size = parse_chunk_size(size_text).ok_or(ReadError::Http(400))?;
            if size == 0 {
                // Discard trailer fields up to the terminating blank line.
                while !self.read_line()?.is_empty() {}
                return Ok(body);
            }
            if size > self.options.max_body_bytes - body.len() {
                return Err(ReadError::Http(413));
            }
            body.extend_from_slice(&self.take(size)?);
            if !self.read_line()?.is_empty() {
                return Err(ReadError::Http(400));
            }
        }
    }
}

/// Parses a `Content-Length` value: decimal digits only.
fn parse_content_length(text: &str) -> ReadResult<usize> {
    if text.is_empty() || !text.bytes().all(|c| c.is_ascii_digit()) {
        return Err(ReadError::Http(400));
    }
    // Only overflow can fail here; treat it as an oversized body.
    text.parse().map_err(|_| ReadError::Http(413))
}

/// Parses a chunk size: hexadecimal digits only.
fn parse_chunk_size(text: &[u8]) -> Option<usize> {
    if text.is_empty() || !text.iter().all(u8::is_ascii_hexdigit) {
        return None;
    }
    usize::from_str_radix(std::str::from_utf8(text).ok()?, 16).ok()
}

/// One-request-per-connection HTTP server listening on 127.0.0.1.
pub struct Server<H> {
    options: Arc<ServerOptions>,
    handler: Arc<H>,
    listener: TcpListener,
}

impl<H> Server<H>
where
    H: Fn(Request) -> Response + Send + Sync + 'static,
{
    /// Binds and listens on the configured port.
    pub fn bind(options: ServerOptions, handler: H) -> io::Result<Self> {
        let listener = TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, options.port)))?;
        Ok(Self {
            options: Arc::new(options),
            handler: Arc::new(handler),
            listener,
        })
    }

    /// Accept loop; does not return under normal operation.
    pub fn run(&self) -> ! {
        loop {
            let stream = match self.listener.accept() {
                Ok((stream, _)) => stream,
                Err(e) => {
                    if !matches!(
                        e.kind(),
                        ErrorKind::Interrupted | ErrorKind::ConnectionAborted
                    ) {
                        eprintln!("accept: {e}");
                        // Typically descriptor exhaustion: back off briefly before retrying.
                        thread::sleep(ACCEPT_BACKOFF);
                    }
                    continue;
                }
            };
            let options = Arc::clone(&self.options);
            let handler = Arc::clone(&self.handler);
            if let Err(e) = thread::Builder::new()
                .spawn(move || handle_connection(stream, &options, handler.as_ref()))
            {
                eprintln!("failed to spawn connection thread: {e}");
            }
        }
    }
}

fn configure(stream: &TcpStream, timeout: Duration) -> io::Result<()> {
    stream.set_read_timeout(Some(timeout))?;
    stream.set_write_timeout(Some(timeout))?;
    stream.set_nodelay(true)
}

fn handle_connection<H>(stream: TcpStream, options: &ServerOptions, handler: &H)
where
    H: Fn(Request) -> Response,
{
    if let Err(e) = configure(&stream, options.io_timeout) {
        eprintln!("socket setup: {e}");
        return;
    }
    let mut conn = Connection::new(stream, options);

    let (response, include_body) = match conn.read_request() {
        Ok(request) => {
            let include_body = request.method != "HEAD";
            let response = panic::catch_unwind(AssertUnwindSafe(|| handler(request)))
                .unwrap_or_else(|_| Response::text(500, "Internal Server Error"));
            (response, include_body)
        }
        Err(ReadError::Http(status)) => (Response::text(status, http::reason_phrase(status)), true),
        // Peer went away; nothing more to do.
        Err(ReadError::Closed) => return,
    };

    if conn.send_response(&response, include_body).is_ok() {
        conn.linger_close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn content_length_parsing() {
        assert_eq!(parse_content_length("12").unwrap(), 12);
        assert!(matches!(
            parse_content_length(""),
            Err(ReadError::Http(400))
        ));
        assert!(matches!(
            parse_content_length("+1"),
            Err(ReadError::Http(400))
        ));
        assert!(matches!(
            parse_content_length("1 2"),
            Err(ReadError::Http(400))
        ));
        assert!(matches!(
            parse_content_length("99999999999999999999999"),
            Err(ReadError::Http(413))
        ));
    }

    #[test]
    fn chunk_size_parsing() {
        assert_eq!(parse_chunk_size(b"1aF"), Some(0x1af));
        assert_eq!(parse_chunk_size(b""), None);
        assert_eq!(parse_chunk_size(b"+1"), None);
        assert_eq!(parse_chunk_size(b"0x1"), None);
    }
}
