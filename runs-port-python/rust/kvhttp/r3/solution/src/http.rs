//! Minimal HTTP/1.1 request parsing and response encoding.

use std::collections::HashMap;
use std::fmt::Write as _;
use std::io;

use bytes::{Bytes, BytesMut};
use tokio::io::{AsyncRead, AsyncReadExt};

/// Largest request body accepted, in bytes.
pub const MAX_BODY_BYTES: usize = 1024 * 1024;
/// Largest request head (request line plus headers) accepted, in bytes.
pub const MAX_HEADER_BYTES: usize = 64 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Ok,
    Created,
    NoContent,
    BadRequest,
    NotFound,
    MethodNotAllowed,
    ContentTooLarge,
    RequestHeaderFieldsTooLarge,
    NotImplemented,
}

impl Status {
    pub fn code(self) -> u16 {
        match self {
            Self::Ok => 200,
            Self::Created => 201,
            Self::NoContent => 204,
            Self::BadRequest => 400,
            Self::NotFound => 404,
            Self::MethodNotAllowed => 405,
            Self::ContentTooLarge => 413,
            Self::RequestHeaderFieldsTooLarge => 431,
            Self::NotImplemented => 501,
        }
    }

    pub fn reason(self) -> &'static str {
        match self {
            Self::Ok => "OK",
            Self::Created => "Created",
            Self::NoContent => "No Content",
            Self::BadRequest => "Bad Request",
            Self::NotFound => "Not Found",
            Self::MethodNotAllowed => "Method Not Allowed",
            Self::ContentTooLarge => "Content Too Large",
            Self::RequestHeaderFieldsTooLarge => "Request Header Fields Too Large",
            Self::NotImplemented => "Not Implemented",
        }
    }
}

/// Why a request could not be read.
#[derive(Debug)]
pub enum ReadError {
    /// The request is malformed or unacceptable; answer with this status.
    Http(Status),
    /// The client went away or the socket failed; nothing useful to send.
    Io(io::Error),
}

impl std::fmt::Display for ReadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Http(status) => write!(f, "{} {}", status.code(), status.reason()),
            Self::Io(e) => write!(f, "i/o error: {e}"),
        }
    }
}

impl std::error::Error for ReadError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Http(_) => None,
            Self::Io(e) => Some(e),
        }
    }
}

impl From<io::Error> for ReadError {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

impl From<Status> for ReadError {
    fn from(s: Status) -> Self {
        Self::Http(s)
    }
}

#[derive(Debug)]
pub struct Request {
    pub method: String,
    pub path: String,
    pub body: Bytes,
}

#[derive(Debug)]
pub struct Response {
    pub status: Status,
    pub headers: Vec<(&'static str, String)>,
    pub body: Bytes,
}

impl Response {
    pub fn empty(status: Status) -> Self {
        Self {
            status,
            headers: Vec::new(),
            body: Bytes::new(),
        }
    }

    pub fn with_body(status: Status, content_type: &str, body: impl Into<Bytes>) -> Self {
        Self {
            status,
            headers: vec![("Content-Type", content_type.to_owned())],
            body: body.into(),
        }
    }

    pub fn header(mut self, name: &'static str, value: impl Into<String>) -> Self {
        self.headers.push((name, value.into()));
        self
    }

    /// Serializes the status line and headers. The connection is always
    /// closed after one response, which the `Connection` header announces.
    pub fn encode_head(&self) -> Vec<u8> {
        let mut head = format!(
            "HTTP/1.1 {} {}\r\n",
            self.status.code(),
            self.status.reason()
        );
        for (name, value) in &self.headers {
            let _ = write!(head, "{name}: {value}\r\n");
        }
        let _ = write!(
            head,
            "Content-Length: {}\r\nConnection: close\r\n\r\n",
            self.body.len()
        );
        head.into_bytes()
    }
}

/// Buffered reader over a byte stream with delimiter and exact-length reads.
pub struct StreamReader<R> {
    inner: R,
    buf: BytesMut,
}

impl<R: AsyncRead + Unpin> StreamReader<R> {
    pub fn new(inner: R) -> Self {
        Self {
            inner,
            buf: BytesMut::with_capacity(8 * 1024),
        }
    }

    /// Reads more data into the buffer, failing on end of stream.
    async fn fill(&mut self) -> io::Result<()> {
        if self.inner.read_buf(&mut self.buf).await? == 0 {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        Ok(())
    }

    /// Reads up to and including `sep`. Fails with 431 if `sep` does not start
    /// within the first `limit` bytes.
    async fn read_until(&mut self, sep: &[u8], limit: usize) -> Result<Bytes, ReadError> {
        let mut searched = 0;
        loop {
            if let Some(pos) = find(&self.buf[searched..], sep).map(|p| p + searched) {
                if pos > limit {
                    return Err(Status::RequestHeaderFieldsTooLarge.into());
                }
                return Ok(self.buf.split_to(pos + sep.len()).freeze());
            }
            searched = (self.buf.len() + 1).saturating_sub(sep.len());
            if searched > limit {
                return Err(Status::RequestHeaderFieldsTooLarge.into());
            }
            self.fill().await?;
        }
    }

    /// Reads exactly `n` bytes.
    async fn read_exact(&mut self, n: usize) -> io::Result<Bytes> {
        if self.buf.len() < n {
            self.buf.reserve(n - self.buf.len());
        }
        while self.buf.len() < n {
            self.fill().await?;
        }
        Ok(self.buf.split_to(n).freeze())
    }

    /// Reads and parses one request.
    pub async fn read_request(&mut self) -> Result<Request, ReadError> {
        let head = self.read_until(b"\r\n\r\n", MAX_HEADER_BYTES).await?;
        let head = latin1(&head[..head.len() - 4]);
        let mut lines = head.split("\r\n");

        let request_line = lines.next().unwrap_or_default();
        let parts: Vec<&str> = request_line.split(' ').collect();
        let [method, target, version] = parts[..] else {
            return Err(Status::BadRequest.into());
        };
        if !version.starts_with("HTTP/") {
            return Err(Status::BadRequest.into());
        }

        // Names are lowercased; a repeated header keeps its last value.
        let mut headers = HashMap::new();
        for line in lines {
            let Some((name, value)) = line.split_once(':') else {
                return Err(Status::BadRequest.into());
            };
            if name.is_empty() || name != name.trim() {
                return Err(Status::BadRequest.into());
            }
            headers.insert(name.to_lowercase(), value.trim().to_owned());
        }

        let path = target.split_once('?').map_or(target, |(p, _)| p).to_owned();
        let body = match headers.get("transfer-encoding") {
            Some(te) if te.eq_ignore_ascii_case("chunked") => self.read_chunked().await?,
            Some(_) => return Err(Status::NotImplemented.into()),
            None => {
                self.read_fixed(headers.get("content-length").map(String::as_str))
                    .await?
            }
        };

        Ok(Request {
            method: method.to_owned(),
            path,
            body,
        })
    }

    async fn read_fixed(&mut self, raw_length: Option<&str>) -> Result<Bytes, ReadError> {
        let Some(raw) = raw_length else {
            return Ok(Bytes::new());
        };
        if raw.is_empty() || !raw.bytes().all(|b| b.is_ascii_digit()) {
            return Err(Status::BadRequest.into());
        }
        // All-digit strings only fail to parse on overflow, which is too large anyway.
        let length = raw.parse::<usize>().unwrap_or(usize::MAX);
        if length > MAX_BODY_BYTES {
            return Err(Status::ContentTooLarge.into());
        }
        Ok(self.read_exact(length).await?)
    }

    async fn read_chunked(&mut self) -> Result<Bytes, ReadError> {
        let mut body = BytesMut::new();
        loop {
            let line = self.read_until(b"\r\n", MAX_HEADER_BYTES).await?;
            let size_field = line.split(|&b| b == b';').next().unwrap_or_default();
            let size = parse_chunk_size(size_field.trim_ascii()).ok_or(Status::BadRequest)?;
            if size == 0 {
                // Discard trailers up to the terminating blank line.
                while &self.read_until(b"\r\n", MAX_HEADER_BYTES).await?[..] != b"\r\n" {}
                return Ok(body.freeze());
            }
            if size > MAX_BODY_BYTES - body.len() {
                return Err(Status::ContentTooLarge.into());
            }
            let chunk = self.read_exact(size).await?;
            body.extend_from_slice(&chunk);
            if &self.read_exact(2).await?[..] != b"\r\n" {
                return Err(Status::BadRequest.into());
            }
        }
    }
}

fn parse_chunk_size(field: &[u8]) -> Option<usize> {
    let digits = std::str::from_utf8(field).ok()?;
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    // Overflow means the chunk is far beyond the body limit.
    Some(usize::from_str_radix(digits, 16).unwrap_or(usize::MAX))
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

/// Decodes bytes as ISO-8859-1, which maps every byte to a code point.
fn latin1(bytes: &[u8]) -> String {
    bytes.iter().map(|&b| char::from(b)).collect()
}

#[cfg(test)]
impl<R> StreamReader<R> {
    /// Bytes read from the stream but not yet consumed.
    fn remaining(&self) -> &[u8] {
        &self.buf
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn parse(raw: &[u8]) -> Result<Request, ReadError> {
        StreamReader::new(raw).read_request().await
    }

    fn status_of(r: Result<Request, ReadError>) -> Status {
        match r {
            Err(ReadError::Http(s)) => s,
            other => panic!("expected http error, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn parses_fixed_body() {
        let raw = b"PUT /kv/a?x=1 HTTP/1.1\r\nContent-Length: 5\r\nX-A:  b \r\n\r\nhelloEXTRA";
        let mut reader = StreamReader::new(&raw[..]);
        let req = reader.read_request().await.unwrap();
        assert_eq!(req.method, "PUT");
        assert_eq!(req.path, "/kv/a");
        assert_eq!(&req.body[..], b"hello");
        assert_eq!(reader.remaining(), b"EXTRA");
    }

    #[tokio::test]
    async fn parses_chunked_body() {
        let raw = b"PUT /kv/a HTTP/1.1\r\nTransfer-Encoding: Chunked\r\n\r\n3;ext\r\nabc\r\n2\r\nde\r\n0\r\nT: v\r\n\r\n";
        assert_eq!(&parse(raw).await.unwrap().body[..], b"abcde");
    }

    #[tokio::test]
    async fn rejects_malformed() {
        assert_eq!(status_of(parse(b"GET /\r\n\r\n").await), Status::BadRequest);
        assert_eq!(
            status_of(parse(b"GET / FTP/1\r\n\r\n").await),
            Status::BadRequest
        );
        assert_eq!(
            status_of(parse(b"GET / HTTP/1.1\r\nnocolon\r\n\r\n").await),
            Status::BadRequest
        );
        assert_eq!(
            status_of(parse(b"GET / HTTP/1.1\r\nA :b\r\n\r\n").await),
            Status::BadRequest
        );
        assert_eq!(
            status_of(parse(b"GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n").await),
            Status::BadRequest
        );
        assert_eq!(
            status_of(parse(b"GET / HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n").await),
            Status::NotImplemented
        );
        assert_eq!(
            status_of(parse(b"PUT / HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n").await),
            Status::ContentTooLarge
        );
    }

    #[tokio::test]
    async fn rejects_oversized_head() {
        let mut raw = b"GET / HTTP/1.1\r\nX: ".to_vec();
        raw.resize(MAX_HEADER_BYTES + 100, b'a');
        raw.extend_from_slice(b"\r\n\r\n");
        assert_eq!(
            status_of(parse(&raw).await),
            Status::RequestHeaderFieldsTooLarge
        );
    }

    #[tokio::test]
    async fn truncated_body_is_io_error() {
        let r = parse(b"PUT / HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc").await;
        assert!(matches!(r, Err(ReadError::Io(_))));
    }

    #[test]
    fn encodes_response() {
        let resp = Response::with_body(Status::Ok, "text/plain", "ok");
        assert_eq!(
            resp.encode_head(),
            b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\n"
        );
    }
}
