//! Connection handling and routing.

use std::io::{self, ErrorKind, Read, Write};
use std::net::{Shutdown, TcpStream};
use std::time::Duration;

use crate::http::{self, RequestHead, Response, Status};
use crate::store::{PutOutcome, Store};

const MAX_HEADER_BYTES: usize = 16 * 1024;
const MAX_KEY_LEN: usize = 64;
const MAX_VALUE_BYTES: usize = 1 << 20;
const IO_TIMEOUT: Duration = Duration::from_secs(10);
/// Upper bound on bytes discarded while waiting for the peer to close.
const DRAIN_LIMIT: u64 = 4 * 1024 * 1024;

/// Serves a single request on `stream`, then closes it gracefully.
pub fn handle_connection(store: &Store, mut stream: TcpStream) {
    // Best effort: failures here only affect timeouts and latency.
    let _ = stream.set_read_timeout(Some(IO_TIMEOUT));
    let _ = stream.set_write_timeout(Some(IO_TIMEOUT));
    let _ = stream.set_nodelay(true);

    // Write errors mean the client went away; there is nobody left to tell.
    let _ = serve(store, &mut stream);
    lingering_close(stream);
}

fn is_timeout(e: &io::Error) -> bool {
    matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut)
}

fn serve(store: &Store, stream: &mut TcpStream) -> io::Result<()> {
    let mut buf = vec![0u8; MAX_HEADER_BYTES];
    let mut used = 0;

    let head_end = loop {
        if used == buf.len() {
            return Response::empty(Status::HeaderFieldsTooLarge).write_to(stream);
        }
        let n = match stream.read(&mut buf[used..]) {
            Ok(0) => return Ok(()),
            Ok(n) => n,
            Err(e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(e) if is_timeout(&e) && used > 0 => {
                return Response::empty(Status::RequestTimeout).write_to(stream);
            }
            Err(_) => return Ok(()),
        };
        // The terminator may straddle the previous read.
        let from = used.saturating_sub(3);
        used += n;
        if let Some(pos) = http::find_head_end(&buf[from..used]) {
            break from + pos;
        }
    };

    let head = match http::parse_head(&buf[..head_end]) {
        Ok(head) => head,
        Err(status) => return Response::empty(status).write_to(stream),
    };
    let extra = &buf[head_end + 4..used];
    route(store, stream, &head, extra)
}

fn valid_key(key: &[u8]) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .iter()
            .all(|&c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
}

fn route(
    store: &Store,
    stream: &mut TcpStream,
    req: &RequestHead<'_>,
    extra: &[u8],
) -> io::Result<()> {
    let method = req.method;
    match req.target {
        b"/health" => match method {
            b"GET" => {
                Response::with_body(Status::Ok, "text/plain; charset=utf-8", b"ok").write_to(stream)
            }
            _ => Response::not_allowed("GET").write_to(stream),
        },
        b"/kv" => match method {
            b"GET" => {
                let json = keys_to_json(&store.keys());
                Response::with_body(Status::Ok, "application/json", json.as_bytes())
                    .write_to(stream)
            }
            _ => Response::not_allowed("GET").write_to(stream),
        },
        target => match target.strip_prefix(b"/kv/") {
            Some(key) if !valid_key(key) => Response::empty(Status::BadRequest).write_to(stream),
            Some(key) => {
                // valid_key guarantees ASCII.
                let key = std::str::from_utf8(key).expect("validated key is ASCII");
                match method {
                    b"GET" => match store.get(key) {
                        Some(value) => {
                            Response::with_body(Status::Ok, "application/octet-stream", &value)
                                .write_to(stream)
                        }
                        None => Response::empty(Status::NotFound).write_to(stream),
                    },
                    b"PUT" => handle_put(store, stream, key, req.content_length, extra),
                    b"DELETE" => {
                        let status = if store.delete(key) {
                            Status::NoContent
                        } else {
                            Status::NotFound
                        };
                        Response::empty(status).write_to(stream)
                    }
                    _ => Response::not_allowed("GET, PUT, DELETE").write_to(stream),
                }
            }
            None => Response::empty(Status::NotFound).write_to(stream),
        },
    }
}

fn handle_put(
    store: &Store,
    stream: &mut TcpStream,
    key: &str,
    content_length: Option<usize>,
    extra: &[u8],
) -> io::Result<()> {
    let len = content_length.unwrap_or(0);
    if len > MAX_VALUE_BYTES {
        return Response::empty(Status::ContentTooLarge).write_to(stream);
    }

    let have = extra.len().min(len);
    let mut value = Vec::with_capacity(len);
    value.extend_from_slice(&extra[..have]);
    value.resize(len, 0);
    if stream.read_exact(&mut value[have..]).is_err() {
        return Ok(()); // client went away or timed out
    }

    let status = match store.put(key, value) {
        PutOutcome::Created => Status::Created,
        PutOutcome::Replaced => Status::Ok,
    };
    Response::empty(status).write_to(stream)
}

/// Keys are restricted to `[A-Za-z0-9_-]`, so no JSON escaping is needed.
fn keys_to_json(keys: &[String]) -> String {
    let mut json = String::with_capacity(2 + keys.iter().map(|k| k.len() + 3).sum::<usize>());
    json.push('[');
    for (i, key) in keys.iter().enumerate() {
        if i > 0 {
            json.push(',');
        }
        json.push('"');
        json.push_str(key);
        json.push('"');
    }
    json.push(']');
    json
}

/// Half-closes and drains whatever the peer still sends, so closing the socket
/// does not reset the connection before the client has read the response.
fn lingering_close(mut stream: TcpStream) {
    let _ = stream.flush();
    let _ = stream.shutdown(Shutdown::Write);
    let _ = io::copy(&mut (&mut stream).take(DRAIN_LIMIT), &mut io::sink());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_validation() {
        assert!(valid_key(b"a-Z_09"));
        assert!(valid_key(&[b'k'; 64]));
        assert!(!valid_key(&[b'k'; 65]));
        assert!(!valid_key(b""));
        assert!(!valid_key(b"a/b"));
        assert!(!valid_key(b"bad.key"));
    }

    #[test]
    fn json_list() {
        assert_eq!(keys_to_json(&[]), "[]");
        assert_eq!(keys_to_json(&["a".into(), "b".into()]), r#"["a","b"]"#);
    }
}
