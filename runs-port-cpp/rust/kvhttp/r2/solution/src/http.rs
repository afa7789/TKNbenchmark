//! Minimal HTTP/1.1 message types and request-head parsing.

const CRLF: &[u8] = b"\r\n";
const HEAD_TERMINATOR: &[u8] = b"\r\n\r\n";

/// A parsed HTTP request.
#[derive(Debug, Default, Clone)]
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
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }
}

/// An HTTP response. `Content-Length` and `Connection: close` are added on
/// serialization.
#[derive(Debug, Clone)]
pub struct Response {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl Response {
    pub fn new(status: u16, headers: Vec<(String, String)>, body: Vec<u8>) -> Self {
        Self {
            status,
            headers,
            body,
        }
    }

    /// A response with no headers and an empty body.
    pub fn empty(status: u16) -> Self {
        Self::new(status, Vec::new(), Vec::new())
    }

    /// A `text/plain` response.
    pub fn text(status: u16, body: impl Into<String>) -> Self {
        Self::new(
            status,
            vec![("Content-Type".into(), "text/plain; charset=utf-8".into())],
            body.into().into_bytes(),
        )
    }

    pub fn with_header(mut self, name: impl Into<String>, value: impl Into<String>) -> Self {
        self.headers.push((name.into(), value.into()));
        self
    }

    /// Serializes the status line and headers, including `Content-Length` and
    /// `Connection: close`. The body is not included.
    pub fn serialize_head(&self) -> Vec<u8> {
        use std::fmt::Write as _;

        let mut out = String::with_capacity(128 + self.headers.len() * 32);
        let _ = write!(
            out,
            "HTTP/1.1 {} {}\r\n",
            self.status,
            reason_phrase(self.status)
        );
        for (key, value) in &self.headers {
            let _ = write!(out, "{key}: {value}\r\n");
        }
        // 204 responses must not carry a body; Content-Length is omitted there.
        if self.status != 204 {
            let _ = write!(out, "Content-Length: {}\r\n", self.body.len());
        }
        out.push_str("Connection: close\r\n\r\n");
        out.into_bytes()
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
        411 => "Length Required",
        413 => "Content Too Large",
        431 => "Request Header Fields Too Large",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        505 => "HTTP Version Not Supported",
        _ => "Unknown",
    }
}

/// Result of parsing the request head (request line + headers).
#[derive(Debug)]
pub struct ParsedHead {
    pub request: Request,
    /// Bytes consumed, including the final CRLFCRLF.
    pub head_size: usize,
}

/// Why a request head could not be parsed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeadError {
    /// The terminating blank line has not been received yet.
    Incomplete,
    /// The head is complete but malformed.
    Malformed,
}

pub fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

fn is_token_char(c: u8) -> bool {
    c.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&c)
}

fn is_token(s: &[u8]) -> bool {
    !s.is_empty() && s.iter().copied().all(is_token_char)
}

fn trim(s: &[u8]) -> &[u8] {
    let is_ws = |c: &u8| *c == b' ' || *c == b'\t';
    let Some(begin) = s.iter().position(|c| !is_ws(c)) else {
        return &[];
    };
    let end = s.iter().rposition(|c| !is_ws(c)).map_or(begin, |e| e + 1);
    &s[begin..end]
}

fn split_once<'a>(s: &'a [u8], sep: &[u8]) -> (&'a [u8], Option<&'a [u8]>) {
    match find(s, sep) {
        Some(pos) => (&s[..pos], Some(&s[pos + sep.len()..])),
        None => (s, None),
    }
}

fn lossy(s: &[u8]) -> String {
    String::from_utf8_lossy(s).into_owned()
}

/// Parses the request head at the start of `data`.
pub fn parse_head(data: &[u8]) -> Result<ParsedHead, HeadError> {
    let head_end = find(data, HEAD_TERMINATOR).ok_or(HeadError::Incomplete)?;
    let head = &data[..head_end];

    // Request line: METHOD SP request-target SP HTTP-version
    let (request_line, mut rest) = split_once(head, CRLF);
    let mut parts = request_line.splitn(3, |&c| c == b' ');
    let (Some(method), Some(target), Some(version)) = (parts.next(), parts.next(), parts.next())
    else {
        return Err(HeadError::Malformed);
    };
    if !is_token(method) || target.is_empty() || !version.starts_with(b"HTTP/1.") {
        return Err(HeadError::Malformed);
    }

    let mut request = Request {
        method: lossy(method),
        target: lossy(target),
        ..Request::default()
    };

    // Header fields.
    while let Some(remaining) = rest.filter(|r| !r.is_empty()) {
        let (line, next) = split_once(remaining, CRLF);
        rest = next;

        let colon = line
            .iter()
            .position(|&c| c == b':')
            .ok_or(HeadError::Malformed)?;
        let name = &line[..colon];
        if !is_token(name) {
            return Err(HeadError::Malformed);
        }
        request
            .headers
            .push((lossy(name), lossy(trim(&line[colon + 1..]))));
    }

    Ok(ParsedHead {
        request,
        head_size: head_end + HEAD_TERMINATOR.len(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_request_line_and_headers() {
        let data = b"PUT /kv/a HTTP/1.1\r\nHost: x\r\nContent-Length:  5 \r\n\r\nhello";
        let parsed = parse_head(data).unwrap();
        assert_eq!(parsed.head_size, data.len() - 5);
        assert_eq!(parsed.request.method, "PUT");
        assert_eq!(parsed.request.target, "/kv/a");
        assert_eq!(parsed.request.header("content-length"), Some("5"));
    }

    #[test]
    fn rejects_malformed_heads() {
        assert_eq!(
            parse_head(b"GET /\r\n\r\n").unwrap_err(),
            HeadError::Malformed
        );
        assert_eq!(
            parse_head(b"GET / FTP/1.0\r\n\r\n").unwrap_err(),
            HeadError::Malformed
        );
        assert_eq!(
            parse_head(b"GET / HTTP/1.1\r\nBad Header: x\r\n\r\n").unwrap_err(),
            HeadError::Malformed
        );
        assert_eq!(
            parse_head(b"GET / HTTP/1.1\r\n").unwrap_err(),
            HeadError::Incomplete
        );
    }

    #[test]
    fn omits_content_length_for_204() {
        let head = String::from_utf8(Response::empty(204).serialize_head()).unwrap();
        assert!(!head.contains("Content-Length"));
        let head = String::from_utf8(Response::text(200, "ok").serialize_head()).unwrap();
        assert!(head.contains("Content-Length: 2\r\n"));
    }
}
