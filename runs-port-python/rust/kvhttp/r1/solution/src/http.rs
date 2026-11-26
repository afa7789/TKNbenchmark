//! Minimal HTTP/1.1 request parsing and response encoding.
//!
//! Exactly one request is read per connection; every response carries an exact
//! `Content-Length` (except `204`) and `Connection: close`.

use std::collections::HashMap;
use std::io;

use bytes::Bytes;
use tokio::io::{AsyncBufRead, AsyncBufReadExt, AsyncReadExt};

/// Largest accepted request body, in bytes.
pub const MAX_BODY_BYTES: usize = 1024 * 1024;
/// Largest accepted request head (request line plus headers), in bytes.
pub const MAX_HEAD_BYTES: usize = 64 * 1024;

/// HTTP status codes used by the server.
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
        }
    }

    fn has_body(self) -> bool {
        self != Self::NoContent
    }
}

/// A parsed request.
#[derive(Debug)]
pub struct Request {
    pub method: String,
    pub path: String,
    /// Header names are lower-cased; on duplicates the last value wins.
    #[allow(dead_code)]
    pub headers: HashMap<String, String>,
    pub body: Bytes,
}

/// A response ready to be encoded.
#[derive(Debug)]
pub struct Response {
    pub status: Status,
    pub body: Bytes,
    pub headers: Vec<(&'static str, String)>,
}

impl Response {
    pub fn new(status: Status) -> Self {
        Self {
            status,
            body: Bytes::new(),
            headers: Vec::new(),
        }
    }

    pub fn with_body(status: Status, content_type: &str, body: impl Into<Bytes>) -> Self {
        Self::new(status)
            .body(body)
            .header("Content-Type", content_type)
    }

    pub fn body(mut self, body: impl Into<Bytes>) -> Self {
        self.body = body.into();
        self
    }

    pub fn header(mut self, name: &'static str, value: impl Into<String>) -> Self {
        self.headers.push((name, value.into()));
        self
    }

    /// Serialise the status line and headers. The body is written separately so
    /// large values are never copied.
    pub fn encode_head(&self) -> Vec<u8> {
        use std::fmt::Write;

        let mut head = format!(
            "HTTP/1.1 {} {}\r\n",
            self.status.code(),
            self.status.reason()
        );
        if self.status.has_body() {
            let _ = write!(head, "Content-Length: {}\r\n", self.body.len());
        }
        head.push_str("Connection: close\r\n");
        for (name, value) in &self.headers {
            let _ = write!(head, "{name}: {value}\r\n");
        }
        head.push_str("\r\n");
        head.into_bytes()
    }
}

/// Why a request could not be read.
#[derive(Debug)]
pub enum ReadError {
    /// The request is malformed or too large; reply with this status.
    Http(Status),
    /// The peer went away or the socket failed; nothing can be sent.
    Disconnected,
}

impl From<io::Error> for ReadError {
    fn from(_: io::Error) -> Self {
        Self::Disconnected
    }
}

impl From<Status> for ReadError {
    fn from(status: Status) -> Self {
        Self::Http(status)
    }
}

/// Decode bytes as Latin-1, which maps every byte to one char.
fn latin1(bytes: &[u8]) -> String {
    bytes.iter().map(|&b| char::from(b)).collect()
}

/// Read bytes up to and including the first `delim`, failing with `too_large`
/// once more than `limit` bytes have been consumed without finding it.
async fn read_until_seq<R>(
    reader: &mut R,
    delim: &[u8],
    limit: usize,
    too_large: Status,
) -> Result<Vec<u8>, ReadError>
where
    R: AsyncBufRead + Unpin,
{
    let last = *delim.last().expect("delimiter must be non-empty");
    let mut buf = Vec::new();
    loop {
        let n = (&mut *reader)
            .take((limit + 1 - buf.len()) as u64)
            .read_until(last, &mut buf)
            .await?;
        if buf.ends_with(delim) {
            return Ok(buf);
        }
        if buf.len() > limit {
            return Err(too_large.into());
        }
        if n == 0 {
            return Err(io::Error::from(io::ErrorKind::UnexpectedEof).into());
        }
    }
}

async fn read_exact_bytes<R>(reader: &mut R, len: usize, out: &mut Vec<u8>) -> io::Result<()>
where
    R: AsyncBufRead + Unpin,
{
    let start = out.len();
    out.resize(start + len, 0);
    reader.read_exact(&mut out[start..]).await?;
    Ok(())
}

/// Read and parse one request from `reader`.
pub async fn read_request<R>(reader: &mut R) -> Result<Request, ReadError>
where
    R: AsyncBufRead + Unpin,
{
    let head = read_until_seq(
        reader,
        b"\r\n\r\n",
        MAX_HEAD_BYTES,
        Status::RequestHeaderFieldsTooLarge,
    )
    .await?;
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

    let chunked = headers
        .get("transfer-encoding")
        .is_some_and(|te| te.to_lowercase().contains("chunked"));
    let body = if chunked {
        read_chunked(reader).await?
    } else {
        let raw = headers.get("content-length").map_or("0", String::as_str);
        let length = parse_content_length(raw)?;
        let mut body = Vec::with_capacity(length);
        read_exact_bytes(reader, length, &mut body).await?;
        body
    };

    let path = target.split_once('?').map_or(target, |(path, _)| path);
    Ok(Request {
        method: method.to_owned(),
        path: path.to_owned(),
        headers,
        body: body.into(),
    })
}

fn parse_content_length(raw: &str) -> Result<usize, Status> {
    if raw.is_empty() || !raw.bytes().all(|b| b.is_ascii_digit()) {
        return Err(Status::BadRequest);
    }
    // All digits, so the only possible parse failure is overflow: far too large.
    match raw.parse::<usize>() {
        Ok(n) if n <= MAX_BODY_BYTES => Ok(n),
        _ => Err(Status::ContentTooLarge),
    }
}

async fn read_chunked<R>(reader: &mut R) -> Result<Vec<u8>, ReadError>
where
    R: AsyncBufRead + Unpin,
{
    let mut body = Vec::new();
    loop {
        let line = read_until_seq(reader, b"\r\n", MAX_HEAD_BYTES, Status::BadRequest).await?;
        let line = &line[..line.len() - 2];
        let size_field = line.split(|&b| b == b';').next().unwrap_or_default();
        let size = parse_chunk_size(size_field.trim_ascii())?;

        if size == 0 {
            // Skip trailers up to the terminating blank line.
            while read_until_seq(reader, b"\r\n", MAX_HEAD_BYTES, Status::BadRequest).await?
                != b"\r\n"
            {}
            return Ok(body);
        }
        if body.len() + size > MAX_BODY_BYTES {
            return Err(Status::ContentTooLarge.into());
        }
        read_exact_bytes(reader, size, &mut body).await?;

        let mut crlf = [0u8; 2];
        reader.read_exact(&mut crlf).await?;
        if &crlf != b"\r\n" {
            return Err(Status::BadRequest.into());
        }
    }
}

fn parse_chunk_size(field: &[u8]) -> Result<usize, Status> {
    if field.is_empty() || !field.iter().all(u8::is_ascii_hexdigit) {
        return Err(Status::BadRequest);
    }
    let digits = std::str::from_utf8(field).map_err(|_| Status::BadRequest)?;
    // All hex digits, so the only possible parse failure is overflow.
    usize::from_str_radix(digits, 16).map_err(|_| Status::ContentTooLarge)
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn parse(raw: &[u8]) -> Result<Request, ReadError> {
        let mut reader = raw;
        read_request(&mut reader).await
    }

    fn status(result: Result<Request, ReadError>) -> Status {
        match result {
            Err(ReadError::Http(status)) => status,
            other => panic!("expected HTTP error, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn parses_request_with_body() {
        let req = parse(b"PUT /kv/a?x=1 HTTP/1.1\r\nContent-Length: 5\r\nHost: x\r\n\r\nhello")
            .await
            .unwrap();
        assert_eq!(req.method, "PUT");
        assert_eq!(req.path, "/kv/a");
        assert_eq!(req.headers["host"], "x");
        assert_eq!(&req.body[..], b"hello");
    }

    #[tokio::test]
    async fn parses_chunked_body() {
        let req = parse(
            b"PUT /kv/a HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3;ext\r\nabc\r\n2\r\nde\r\n0\r\nX: y\r\n\r\n",
        )
        .await
        .unwrap();
        assert_eq!(&req.body[..], b"abcde");
    }

    #[tokio::test]
    async fn rejects_malformed_requests() {
        assert_eq!(status(parse(b"GET /\r\n\r\n").await), Status::BadRequest);
        assert_eq!(
            status(parse(b"GET / FTP/1\r\n\r\n").await),
            Status::BadRequest
        );
        assert_eq!(
            status(parse(b"GET / HTTP/1.1\r\nbad\r\n\r\n").await),
            Status::BadRequest
        );
        assert_eq!(
            status(parse(b"GET / HTTP/1.1\r\n X: y\r\n\r\n").await),
            Status::BadRequest
        );
        assert_eq!(
            status(parse(b"GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n").await),
            Status::BadRequest
        );
        assert_eq!(
            status(parse(b"GET / HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n").await),
            Status::ContentTooLarge
        );
    }

    #[tokio::test]
    async fn rejects_oversized_head() {
        let mut raw = b"GET / HTTP/1.1\r\nX: ".to_vec();
        raw.extend(std::iter::repeat_n(b'a', MAX_HEAD_BYTES));
        raw.extend(b"\r\n\r\n");
        assert_eq!(
            status(parse(&raw).await),
            Status::RequestHeaderFieldsTooLarge
        );
    }

    #[tokio::test]
    async fn truncated_request_is_io_error() {
        assert!(matches!(
            parse(b"GET / HTTP/1.1\r\n").await,
            Err(ReadError::Disconnected)
        ));
        assert!(matches!(
            parse(b"PUT /kv/a HTTP/1.1\r\nContent-Length: 9\r\n\r\nabc").await,
            Err(ReadError::Disconnected)
        ));
    }

    #[test]
    fn no_content_omits_length() {
        let head = String::from_utf8(Response::new(Status::NoContent).encode_head()).unwrap();
        assert_eq!(head, "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n");
        let head = String::from_utf8(Response::new(Status::Ok).body("ok").encode_head()).unwrap();
        assert!(head.contains("Content-Length: 2\r\n"));
    }
}
