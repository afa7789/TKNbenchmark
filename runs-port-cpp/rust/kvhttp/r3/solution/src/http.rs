//! Minimal HTTP/1.1 request parsing and response serialisation.

use std::fmt;
use std::io::{self, Read, Write};
use std::sync::Arc;

pub const MAX_HEADER_BYTES: usize = 64 * 1024;
pub const MAX_BODY_BYTES: usize = 1024 * 1024;

const READ_CHUNK: usize = 16 * 1024;

/// A request that cannot be served; carries the status code to reply with.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HttpError(pub u16);

impl fmt::Display for HttpError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} {}", self.0, reason_phrase(self.0))
    }
}

impl std::error::Error for HttpError {}

#[derive(Debug, Default)]
pub struct Request {
    pub method: String,
    pub target: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl Request {
    /// Case-insensitive header lookup; returns the first match.
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

#[derive(Debug, Clone)]
pub enum Body {
    Owned(Vec<u8>),
    Shared(Arc<Vec<u8>>),
}

impl Default for Body {
    fn default() -> Self {
        Body::Owned(Vec::new())
    }
}

impl AsRef<[u8]> for Body {
    fn as_ref(&self) -> &[u8] {
        match self {
            Body::Owned(v) => v,
            Body::Shared(v) => v,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct Response {
    pub status: u16,
    pub content_type: Option<&'static str>,
    pub body: Body,
}

impl Response {
    pub fn status(status: u16) -> Self {
        Self {
            status,
            ..Self::default()
        }
    }

    pub fn with_body(status: u16, content_type: &'static str, body: Body) -> Self {
        Self {
            status,
            content_type: Some(content_type),
            body,
        }
    }

    /// Serialises the response, always with `Connection: close` and (except
    /// for 204) an exact `Content-Length`.
    pub fn write_to<W: Write>(&self, out: &mut W) -> io::Result<()> {
        let body = self.body.as_ref();
        let mut head = Vec::with_capacity(160);
        write!(
            head,
            "HTTP/1.1 {} {}\r\n",
            self.status,
            reason_phrase(self.status)
        )?;
        if let Some(ct) = self.content_type {
            write!(head, "Content-Type: {ct}\r\n")?;
        }
        // 204 must not carry a body or Content-Length framing.
        if self.status != 204 {
            write!(head, "Content-Length: {}\r\n", body.len())?;
        }
        head.extend_from_slice(b"Connection: close\r\n\r\n");

        if body.len() < READ_CHUNK {
            head.extend_from_slice(body);
            out.write_all(&head)?;
        } else {
            out.write_all(&head)?;
            out.write_all(body)?;
        }
        out.flush()
    }
}

pub fn reason_phrase(status: u16) -> &'static str {
    match status {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        408 => "Request Timeout",
        413 => "Content Too Large",
        431 => "Request Header Fields Too Large",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        _ => "Unknown",
    }
}

fn trim(s: &str) -> &str {
    s.trim_matches([' ', '\t'])
}

/// Buffered reader over a byte stream with CRLF line framing.
struct Reader<R> {
    inner: R,
    buf: Vec<u8>,
    pos: usize,
}

impl<R: Read> Reader<R> {
    fn new(inner: R) -> Self {
        Self {
            inner,
            buf: Vec::new(),
            pos: 0,
        }
    }

    fn buffered(&self) -> usize {
        self.buf.len() - self.pos
    }

    /// Reads more bytes into the buffer; returns `false` on EOF.
    fn fill(&mut self) -> Result<bool, HttpError> {
        // Reclaim consumed space before growing.
        if self.pos > 0 && self.pos == self.buf.len() {
            self.buf.clear();
            self.pos = 0;
        }
        let start = self.buf.len();
        self.buf.resize(start + READ_CHUNK, 0);
        loop {
            match self.inner.read(&mut self.buf[start..]) {
                Ok(n) => {
                    self.buf.truncate(start + n);
                    return Ok(n > 0);
                }
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => {
                    self.buf.truncate(start);
                    return Err(HttpError(408)); // timeout or connection error
                }
            }
        }
    }

    /// Returns the next CRLF-terminated line (without terminator).
    fn read_line(&mut self, limit: usize) -> Result<String, HttpError> {
        let mut from = self.pos;
        loop {
            if let Some(i) = self.buf[from..].windows(2).position(|w| w == b"\r\n") {
                let end = from + i;
                let line = String::from_utf8_lossy(&self.buf[self.pos..end]).into_owned();
                self.pos = end + 2;
                return Ok(line);
            }
            // Resume the search where it stopped, allowing for a split "\r\n".
            from = self.buf.len().saturating_sub(1).max(self.pos);
            if self.buffered() > limit {
                return Err(HttpError(431));
            }
            if !self.fill()? {
                return Err(HttpError(400));
            }
        }
    }

    fn read_exact_into(&mut self, n: usize, out: &mut Vec<u8>) -> Result<(), HttpError> {
        while self.buffered() < n {
            if !self.fill()? {
                return Err(HttpError(400));
            }
        }
        out.extend_from_slice(&self.buf[self.pos..self.pos + n]);
        self.pos += n;
        Ok(())
    }
}

fn parse_size(s: &str, radix: u32) -> Result<usize, HttpError> {
    // `from_str_radix` accepts a leading '+', which HTTP does not.
    if s.is_empty() || !s.bytes().all(|b| (b as char).is_digit(radix)) {
        return Err(HttpError(400));
    }
    usize::from_str_radix(s, radix).map_err(|_| HttpError(400))
}

fn read_chunked_body<R: Read>(reader: &mut Reader<R>, body: &mut Vec<u8>) -> Result<(), HttpError> {
    loop {
        let line = reader.read_line(MAX_HEADER_BYTES)?;
        let size_part = line.split_once(';').map_or(line.as_str(), |(s, _)| s);
        let size = parse_size(trim(size_part), 16)?;
        if size == 0 {
            break;
        }
        if size > MAX_BODY_BYTES || body.len() + size > MAX_BODY_BYTES {
            return Err(HttpError(413));
        }
        reader.read_exact_into(size, body)?;
        if !reader.read_line(0)?.is_empty() {
            return Err(HttpError(400));
        }
    }
    // Trailer section, terminated by an empty line.
    let mut total = 0;
    loop {
        let line = reader.read_line(MAX_HEADER_BYTES)?;
        if line.is_empty() {
            return Ok(());
        }
        total += line.len();
        if total > MAX_HEADER_BYTES {
            return Err(HttpError(431));
        }
    }
}

/// Reads one request. Returns `Ok(None)` if the peer closed the connection
/// before sending anything.
pub fn read_request<R: Read>(stream: R) -> Result<Option<Request>, HttpError> {
    let mut reader = Reader::new(stream);
    if !reader.fill()? {
        return Ok(None);
    }

    let mut request_line = reader.read_line(MAX_HEADER_BYTES)?;
    // Tolerate stray blank lines before the request line (RFC 9112 §2.2).
    while request_line.is_empty() {
        request_line = reader.read_line(MAX_HEADER_BYTES)?;
    }
    let mut header_bytes = request_line.len();

    let mut parts = request_line.splitn(3, ' ');
    let (Some(method), Some(target), Some(version)) = (parts.next(), parts.next(), parts.next())
    else {
        return Err(HttpError(400));
    };
    if method.is_empty() || target.is_empty() || !version.starts_with("HTTP/") {
        return Err(HttpError(400));
    }

    let mut req = Request {
        method: method.to_owned(),
        target: target.to_owned(),
        ..Request::default()
    };

    loop {
        let line = reader.read_line(MAX_HEADER_BYTES)?;
        if line.is_empty() {
            break;
        }
        header_bytes += line.len();
        if header_bytes > MAX_HEADER_BYTES {
            return Err(HttpError(431));
        }
        match line.split_once(':') {
            Some((name, value)) if !name.is_empty() => {
                req.headers.push((name.to_owned(), trim(value).to_owned()));
            }
            _ => return Err(HttpError(400)),
        }
    }

    if let Some(te) = req.header("Transfer-Encoding") {
        if !trim(te).eq_ignore_ascii_case("chunked") {
            return Err(HttpError(501));
        }
        let mut body = Vec::new();
        read_chunked_body(&mut reader, &mut body)?;
        req.body = body;
    } else if let Some(cl) = req.header("Content-Length") {
        let length = parse_size(trim(cl), 10)?;
        if length > MAX_BODY_BYTES {
            return Err(HttpError(413));
        }
        let mut body = Vec::with_capacity(length);
        reader.read_exact_into(length, &mut body)?;
        req.body = body;
    }
    Ok(Some(req))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(raw: &[u8]) -> Result<Option<Request>, HttpError> {
        read_request(raw)
    }

    #[test]
    fn parses_content_length_body() {
        let req = parse(b"PUT /kv/a HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
            .unwrap()
            .unwrap();
        assert_eq!(req.method, "PUT");
        assert_eq!(req.target, "/kv/a");
        assert_eq!(req.body, b"hello");
    }

    #[test]
    fn parses_chunked_body() {
        let req = parse(
            b"PUT /kv/a HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nhel\r\n2;x=y\r\nlo\r\n0\r\n\r\n",
        )
        .unwrap()
        .unwrap();
        assert_eq!(req.body, b"hello");
    }

    #[test]
    fn empty_stream_is_none() {
        assert!(parse(b"").unwrap().is_none());
    }

    #[test]
    fn rejects_malformed() {
        assert_eq!(parse(b"GET\r\n\r\n").unwrap_err(), HttpError(400));
        assert_eq!(
            parse(b"PUT /kv/a HTTP/1.1\r\nContent-Length: +1\r\n\r\nx").unwrap_err(),
            HttpError(400)
        );
        assert_eq!(
            parse(b"PUT /kv/a HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n").unwrap_err(),
            HttpError(413)
        );
    }

    #[test]
    fn serialises_response() {
        let mut out = Vec::new();
        Response::with_body(200, "text/plain", Body::Owned(b"ok".to_vec()))
            .write_to(&mut out)
            .unwrap();
        assert_eq!(
            out,
            b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
        );
    }
}
