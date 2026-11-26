//! Minimal HTTP/1.1 request reader and response writer: one request per
//! connection.

use std::fmt::Write as _;
use std::io::{self, Read, Write};

const HEADER_END: &[u8] = b"\r\n\r\n";
const CRLF: &[u8] = b"\r\n";
const CHUNK_SIZE: usize = 16 * 1024;

#[derive(Debug)]
pub struct Request {
    pub method: String,
    pub target: String,
    pub body: Vec<u8>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusCode {
    Ok = 200,
    Created = 201,
    NoContent = 204,
    BadRequest = 400,
    NotFound = 404,
    MethodNotAllowed = 405,
    ContentTooLarge = 413,
    RequestHeaderFieldsTooLarge = 431,
    InternalServerError = 500,
    NotImplemented = 501,
    HttpVersionNotSupported = 505,
}

impl StatusCode {
    pub fn code(self) -> u16 {
        self as u16
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
            Self::InternalServerError => "Internal Server Error",
            Self::NotImplemented => "Not Implemented",
            Self::HttpVersionNotSupported => "HTTP Version Not Supported",
        }
    }
}

/// Response body: either owned bytes or a shared stored value (sent without
/// copying).
#[derive(Debug, Clone)]
pub enum Body {
    Empty,
    Owned(Vec<u8>),
    Shared(std::sync::Arc<[u8]>),
}

impl Body {
    fn as_bytes(&self) -> &[u8] {
        match self {
            Self::Empty => &[],
            Self::Owned(v) => v,
            Self::Shared(v) => v,
        }
    }
}

#[derive(Debug, Clone)]
pub struct Response {
    pub status: StatusCode,
    pub headers: Vec<(&'static str, String)>,
    pub body: Body,
}

impl Response {
    pub fn empty(status: StatusCode) -> Self {
        Self {
            status,
            headers: Vec::new(),
            body: Body::Empty,
        }
    }

    pub fn with_body(status: StatusCode, body: Body, content_type: &str) -> Self {
        Self {
            status,
            headers: vec![("Content-Type", content_type.to_owned())],
            body,
        }
    }

    pub fn text(status: StatusCode, body: impl Into<Vec<u8>>) -> Self {
        Self::with_body(
            status,
            Body::Owned(body.into()),
            "text/plain; charset=utf-8",
        )
    }

    pub fn header(mut self, name: &'static str, value: impl Into<String>) -> Self {
        self.headers.push((name, value.into()));
        self
    }

    /// Writes the full response.
    pub fn write_to(&self, w: &mut impl Write) -> io::Result<()> {
        let body = self.body.as_bytes();
        let mut head = format!(
            "HTTP/1.1 {} {}\r\n",
            self.status.code(),
            self.status.reason()
        );
        for (name, value) in &self.headers {
            head.push_str(name);
            head.push_str(": ");
            head.push_str(value);
            head.push_str("\r\n");
        }
        if self.status != StatusCode::NoContent {
            // Writing into a String cannot fail.
            let _ = write!(head, "Content-Length: {}\r\n", body.len());
        }
        head.push_str("Connection: close\r\n\r\n");

        w.write_all(head.as_bytes())?;
        w.write_all(body)?;
        w.flush()
    }
}

/// Limits applied while reading a request.
#[derive(Debug, Clone, Copy)]
pub struct Limits {
    pub max_header_bytes: usize,
    pub max_body_bytes: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_header_bytes: 64 * 1024,
            max_body_bytes: 1024 * 1024,
        }
    }
}

/// Outcome of reading one request from a connection.
#[derive(Debug)]
pub enum ReadOutcome {
    Request(Request),
    /// The request was malformed; send this response instead.
    Reject(Response),
    /// The peer closed, timed out, or failed before a full request arrived.
    Disconnected,
}

fn reject(status: StatusCode) -> ReadOutcome {
    ReadOutcome::Reject(Response::empty(status))
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

fn trim(s: &[u8]) -> &[u8] {
    let is_ws = |b: &u8| *b == b' ' || *b == b'\t';
    let start = s.iter().position(|b| !is_ws(b)).unwrap_or(s.len());
    let end = s.iter().rposition(|b| !is_ws(b)).map_or(start, |i| i + 1);
    &s[start..end]
}

/// Parses a Content-Length value: ASCII digits only, no sign, no overflow.
fn parse_content_length(value: &[u8]) -> Option<usize> {
    if value.is_empty() || !value.iter().all(u8::is_ascii_digit) {
        return None;
    }
    std::str::from_utf8(value).ok()?.parse().ok()
}

/// Reads and discards `remaining` bytes so the peer sees a clean close rather
/// than a reset when we reply without consuming its body.
fn discard(r: &mut impl Read, remaining: usize) {
    // Errors just mean the peer is gone; nothing more to do.
    let _ = io::copy(&mut r.take(remaining as u64), &mut io::sink());
}

/// Reads exactly one request from `r`.
pub fn read_request(r: &mut impl Read, limits: &Limits) -> ReadOutcome {
    let mut buf = Vec::new();
    let mut chunk = vec![0u8; CHUNK_SIZE];

    let header_end = loop {
        if buf.len() > limits.max_header_bytes {
            return reject(StatusCode::RequestHeaderFieldsTooLarge);
        }
        let n = match r.read(&mut chunk) {
            Ok(0) | Err(_) => return ReadOutcome::Disconnected,
            Ok(n) => n,
        };
        let search_from = buf.len().saturating_sub(HEADER_END.len() - 1);
        buf.extend_from_slice(&chunk[..n]);
        if let Some(pos) = find(&buf[search_from..], HEADER_END) {
            break search_from + pos;
        }
    };
    if header_end > limits.max_header_bytes {
        return reject(StatusCode::RequestHeaderFieldsTooLarge);
    }

    let head = &buf[..header_end];
    let (request_line, mut rest) = match find(head, CRLF) {
        Some(i) => (&head[..i], &head[i + CRLF.len()..]),
        None => (head, &[][..]),
    };

    // request-line = method SP request-target SP HTTP-version
    let mut parts = request_line.splitn(3, |&b| b == b' ');
    let (Some(method), Some(target), Some(version)) = (parts.next(), parts.next(), parts.next())
    else {
        return reject(StatusCode::BadRequest);
    };
    if method.is_empty() || target.is_empty() {
        return reject(StatusCode::BadRequest);
    }
    if !version.starts_with(b"HTTP/1.") {
        return reject(if version.starts_with(b"HTTP/") {
            StatusCode::HttpVersionNotSupported
        } else {
            StatusCode::BadRequest
        });
    }

    let mut content_length: Option<usize> = None;
    while !rest.is_empty() {
        let line = match find(rest, CRLF) {
            Some(i) => {
                let line = &rest[..i];
                rest = &rest[i + CRLF.len()..];
                line
            }
            None => std::mem::take(&mut rest),
        };

        let Some(colon) = line.iter().position(|&b| b == b':').filter(|&c| c > 0) else {
            return reject(StatusCode::BadRequest);
        };
        let name = &line[..colon];
        let value = trim(&line[colon + 1..]);

        if name.eq_ignore_ascii_case(b"Content-Length") {
            let Some(len) = parse_content_length(value) else {
                return reject(StatusCode::BadRequest);
            };
            if content_length.is_some_and(|prev| prev != len) {
                return reject(StatusCode::BadRequest);
            }
            content_length = Some(len);
        } else if name.eq_ignore_ascii_case(b"Transfer-Encoding") {
            return reject(StatusCode::NotImplemented);
        }
    }

    let length = content_length.unwrap_or(0);
    let already = &buf[header_end + HEADER_END.len()..];
    if length > limits.max_body_bytes {
        if already.len() < length {
            discard(r, length - already.len());
        }
        return reject(StatusCode::ContentTooLarge);
    }

    let mut body = Vec::with_capacity(length);
    body.extend_from_slice(&already[..already.len().min(length)]);
    if body.len() < length {
        let missing = length - body.len();
        match r.take(missing as u64).read_to_end(&mut body) {
            Ok(n) if n == missing => {}
            _ => return ReadOutcome::Disconnected, // truncated body: peer is gone
        }
    }

    ReadOutcome::Request(Request {
        method: String::from_utf8_lossy(method).into_owned(),
        target: String::from_utf8_lossy(target).into_owned(),
        body,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read(raw: &[u8]) -> ReadOutcome {
        read_request(&mut &raw[..], &Limits::default())
    }

    fn status_of(outcome: ReadOutcome) -> StatusCode {
        match outcome {
            ReadOutcome::Reject(r) => r.status,
            other => panic!("expected rejection, got {other:?}"),
        }
    }

    #[test]
    fn parses_request_with_body() {
        let ReadOutcome::Request(req) =
            read(b"PUT /kv/a HTTP/1.1\r\ncontent-length:  5 \r\n\r\nhelloextra")
        else {
            panic!("expected request");
        };
        assert_eq!(req.method, "PUT");
        assert_eq!(req.target, "/kv/a");
        assert_eq!(req.body, b"hello");
    }

    #[test]
    fn rejects_malformed() {
        assert_eq!(status_of(read(b"GET /\r\n\r\n")), StatusCode::BadRequest);
        assert_eq!(
            status_of(read(b"GET / HTTP/2\r\n\r\n")),
            StatusCode::HttpVersionNotSupported
        );
        assert_eq!(
            status_of(read(b"GET / HTTP/1.1\r\nContent-Length: +1\r\n\r\n")),
            StatusCode::BadRequest
        );
        assert_eq!(
            status_of(read(
                b"GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
            )),
            StatusCode::NotImplemented
        );
    }

    #[test]
    fn truncated_body_is_disconnect() {
        assert!(matches!(
            read(b"PUT /kv/a HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"),
            ReadOutcome::Disconnected
        ));
    }
}
