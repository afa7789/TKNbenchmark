//! Maps requests onto the key/value API.

use crate::http::{Body, Request, Response};
use crate::store::Store;

const KV_PREFIX: &str = "/kv/";
const MAX_KEY_LENGTH: usize = 64;

/// True if `key` matches `[A-Za-z0-9_-]{1,64}`.
pub fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LENGTH).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Keys are restricted to `[A-Za-z0-9_-]`, so no JSON escaping is required.
fn json_string_array(items: &[String]) -> Vec<u8> {
    let size = 2 + items.iter().map(|s| s.len() + 3).sum::<usize>();
    let mut out = Vec::with_capacity(size);
    out.push(b'[');
    for (i, item) in items.iter().enumerate() {
        if i > 0 {
            out.push(b',');
        }
        out.push(b'"');
        out.extend_from_slice(item.as_bytes());
        out.push(b'"');
    }
    out.push(b']');
    out
}

#[derive(Debug, Default)]
pub struct Router {
    store: Store,
}

impl Router {
    pub fn new(store: Store) -> Self {
        Self { store }
    }

    pub fn handle(&self, request: Request) -> Response {
        let Request {
            method,
            target,
            body,
            ..
        } = request;
        match target.as_str() {
            "/health" => match method.as_str() {
                "GET" => Response::with_body(200, "text/plain", Body::Owned(b"ok".to_vec())),
                _ => Response::status(405),
            },
            "/kv" => match method.as_str() {
                "GET" => Response::with_body(
                    200,
                    "application/json",
                    Body::Owned(json_string_array(&self.store.keys())),
                ),
                _ => Response::status(405),
            },
            path => match path.strip_prefix(KV_PREFIX) {
                Some(key) if is_valid_key(key) => self.handle_key(&method, key, body),
                Some(_) => Response::status(400),
                None => Response::status(404),
            },
        }
    }

    fn handle_key(&self, method: &str, key: &str, body: Vec<u8>) -> Response {
        match method {
            "GET" => match self.store.get(key) {
                Some(value) => {
                    Response::with_body(200, "application/octet-stream", Body::Shared(value))
                }
                None => Response::status(404),
            },
            "PUT" => {
                let created = self.store.put(key, body);
                Response::status(if created { 201 } else { 200 })
            }
            "DELETE" => Response::status(if self.store.remove(key) { 204 } else { 404 }),
            _ => Response::status(405),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn req(method: &str, target: &str, body: &[u8]) -> Request {
        Request {
            method: method.into(),
            target: target.into(),
            body: body.to_vec(),
            ..Request::default()
        }
    }

    #[test]
    fn validates_keys() {
        assert!(is_valid_key("a-Z_09"));
        assert!(is_valid_key(&"k".repeat(64)));
        assert!(!is_valid_key(""));
        assert!(!is_valid_key(&"k".repeat(65)));
        assert!(!is_valid_key("a/b"));
        assert!(!is_valid_key("a.b"));
        assert!(!is_valid_key("é"));
    }

    #[test]
    fn routes() {
        let r = Router::default();
        assert_eq!(r.handle(req("GET", "/health", b"")).status, 200);
        assert_eq!(r.handle(req("POST", "/health", b"")).status, 405);
        assert_eq!(r.handle(req("GET", "/nope", b"")).status, 404);
        assert_eq!(r.handle(req("GET", "/kv/", b"")).status, 400);
        assert_eq!(r.handle(req("GET", "/kv/a/b", b"")).status, 400);
        assert_eq!(r.handle(req("PUT", "/kv/b", b"2")).status, 201);
        assert_eq!(r.handle(req("PUT", "/kv/a", b"1")).status, 201);
        assert_eq!(r.handle(req("PUT", "/kv/a", b"1")).status, 200);
        assert_eq!(r.handle(req("PATCH", "/kv/a", b"")).status, 405);
        assert_eq!(r.handle(req("POST", "/kv", b"")).status, 405);
        let list = r.handle(req("GET", "/kv", b""));
        assert_eq!(list.body.as_ref(), br#"["a","b"]"#);
        assert_eq!(r.handle(req("DELETE", "/kv/a", b"")).status, 204);
        assert_eq!(r.handle(req("DELETE", "/kv/a", b"")).status, 404);
        assert_eq!(r.handle(req("GET", "/kv/a", b"")).status, 404);
    }
}
