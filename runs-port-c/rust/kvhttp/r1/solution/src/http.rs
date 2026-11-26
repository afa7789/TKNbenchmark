//! Minimal HTTP/1.1 request-head parsing and response serialization.

use std::io::{self, Write};

/// Response status codes used by the server.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Ok,
    Created,
    NoContent,
    BadRequest,
    NotFound,
    MethodNotAllowed,
    RequestTimeout,
    ContentTooLarge,
    HeaderFieldsTooLarge,
    NotImplemented,
    VersionNotSupported,
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
            Self::RequestTimeout => 408,
            Self::ContentTooLarge => 413,
            Self::HeaderFieldsTooLarge => 431,
            Self::NotImplemented => 501,
            Self::VersionNotSupported => 505,
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
            Self::RequestTimeout => "Request Timeout",
            Self::ContentTooLarge => "Content Too Large",
            Self::HeaderFieldsTooLarge => "Request Header Fields Too Large",
            Self::NotImplemented => "Not Implemented",
            Self::VersionNotSupported => "HTTP Version Not Supported",
        }
    }
}

/// A response; always sent with `Content-Length` and `Connection: close`.
#[derive(Debug)]
pub struct Response<'a> {
    pub status: Status,
    pub content_type: Option<&'static str>,
    /// Value of the `Allow` header, set on 405 responses.
    pub allow: Option<&'static str>,
    pub body: &'a [u8],
}

impl<'a> Response<'a> {
    pub fn empty(status: Status) -> Self {
        Self {
            status,
            content_type: None,
            allow: None,
            body: &[],
        }
    }

    pub fn with_body(status: Status, content_type: &'static str, body: &'a [u8]) -> Self {
        Self {
            status,
            content_type: Some(content_type),
            allow: None,
            body,
        }
    }

    pub fn not_allowed(allow: &'static str) -> Self {
        Self {
            allow: Some(allow),
            ..Self::empty(Status::MethodNotAllowed)
        }
    }

    pub fn write_to(&self, w: &mut impl Write) -> io::Result<()> {
        let mut head = format!(
            "HTTP/1.1 {} {}\r\nContent-Length: {}\r\nConnection: close\r\n",
            self.status.code(),
            self.status.reason(),
            self.body.len()
        );
        if let Some(ct) = self.content_type {
            head.push_str("Content-Type: ");
            head.push_str(ct);
            head.push_str("\r\n");
        }
        if let Some(allow) = self.allow {
            head.push_str("Allow: ");
            head.push_str(allow);
            head.push_str("\r\n");
        }
        head.push_str("\r\n");

        if self.body.len() <= 16 * 1024 {
            // Small responses go out in a single write.
            let mut buf = head.into_bytes();
            buf.extend_from_slice(self.body);
            w.write_all(&buf)
        } else {
            w.write_all(head.as_bytes())?;
            w.write_all(self.body)
        }
    }
}

/// A parsed request line plus the header fields the server cares about.
#[derive(Debug, PartialEq, Eq)]
pub struct RequestHead<'a> {
    pub method: &'a [u8],
    pub target: &'a [u8],
    pub content_length: Option<usize>,
}

/// Returns the offset of the CRLFCRLF that terminates the header block.
pub fn find_head_end(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n")
}

fn is_tchar(c: u8) -> bool {
    c.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&c)
}

fn is_token(s: &[u8]) -> bool {
    !s.is_empty() && s.iter().copied().all(is_tchar)
}

fn trim_ows(s: &[u8]) -> &[u8] {
    let is_ows = |c: &u8| *c == b' ' || *c == b'\t';
    let start = s.iter().position(|c| !is_ows(c)).unwrap_or(s.len());
    let end = s.iter().rposition(|c| !is_ows(c)).map_or(start, |i| i + 1);
    &s[start..end]
}

/// Parses a non-empty run of ASCII digits, rejecting overflow.
fn parse_decimal(s: &[u8]) -> Option<usize> {
    if s.is_empty() {
        return None;
    }
    s.iter().try_fold(0usize, |acc, &c| {
        let digit = (c as char).to_digit(10)?;
        acc.checked_mul(10)?.checked_add(digit as usize)
    })
}

/// Parses the header block (without the terminating CRLFCRLF).
pub fn parse_head(head: &[u8]) -> Result<RequestHead<'_>, Status> {
    if head.contains(&0) {
        return Err(Status::BadRequest);
    }

    let line_end = head.iter().position(|&c| c == b'\r').unwrap_or(head.len());
    let (line, mut rest) = head.split_at(line_end);

    // Request line: method SP target SP version
    let mut parts = line.splitn(3, |&c| c == b' ');
    let method = parts.next().unwrap_or_default();
    let target = parts.next().ok_or(Status::BadRequest)?;
    let version = parts.next().ok_or(Status::BadRequest)?;
    if method.is_empty() || target.is_empty() || !is_token(method) {
        return Err(Status::BadRequest);
    }
    if version.len() != 8 || !version.starts_with(b"HTTP/1.") {
        return Err(if version.starts_with(b"HTTP/") {
            Status::VersionNotSupported
        } else {
            Status::BadRequest
        });
    }

    let mut content_length = None;
    let mut chunked = false;
    while !rest.is_empty() {
        rest = rest.strip_prefix(b"\r\n").ok_or(Status::BadRequest)?;
        let eol = rest.iter().position(|&c| c == b'\r').unwrap_or(rest.len());
        let (field, tail) = rest.split_at(eol);
        rest = tail;

        let colon = field
            .iter()
            .position(|&c| c == b':')
            .ok_or(Status::BadRequest)?;
        let (name, value) = (&field[..colon], trim_ows(&field[colon + 1..]));
        if !is_token(name) {
            return Err(Status::BadRequest);
        }

        if name.eq_ignore_ascii_case(b"Content-Length") {
            let len = parse_decimal(value).ok_or(Status::BadRequest)?;
            if content_length.is_some_and(|prev| prev != len) {
                return Err(Status::BadRequest);
            }
            content_length = Some(len);
        } else if name.eq_ignore_ascii_case(b"Transfer-Encoding") {
            chunked = true;
        }
    }

    if chunked {
        return Err(if content_length.is_some() {
            Status::BadRequest
        } else {
            Status::NotImplemented
        });
    }
    Ok(RequestHead {
        method,
        target,
        content_length,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_basic_request() {
        let head = parse_head(b"PUT /kv/a HTTP/1.1\r\nHost: x\r\ncontent-length:  5 ").unwrap();
        assert_eq!(head.method, b"PUT");
        assert_eq!(head.target, b"/kv/a");
        assert_eq!(head.content_length, Some(5));
    }

    #[test]
    fn rejects_malformed() {
        assert_eq!(parse_head(b"GET /x"), Err(Status::BadRequest));
        assert_eq!(
            parse_head(b"GET /x HTTP/2.0"),
            Err(Status::VersionNotSupported)
        );
        assert_eq!(parse_head(b"GET /x FOO"), Err(Status::BadRequest));
        assert_eq!(
            parse_head(b"GET /x HTTP/1.1\r\nbad"),
            Err(Status::BadRequest)
        );
        assert_eq!(
            parse_head(b"GET /x HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2"),
            Err(Status::BadRequest)
        );
        assert_eq!(
            parse_head(b"GET /x HTTP/1.1\r\nTransfer-Encoding: chunked"),
            Err(Status::NotImplemented)
        );
    }

    #[test]
    fn decimal_overflow() {
        assert_eq!(parse_decimal(b"99999999999999999999999"), None);
        assert_eq!(parse_decimal(b"12"), Some(12));
        assert_eq!(parse_decimal(b"+1"), None);
    }
}
