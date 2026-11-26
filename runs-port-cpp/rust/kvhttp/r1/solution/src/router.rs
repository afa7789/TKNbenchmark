//! Maps requests onto the key/value API described in SPEC.md.

use crate::http::{Body, Request, Response, StatusCode};
use crate::store::KvStore;

const KV_PREFIX: &str = "/kv/";
const MAX_KEY_LEN: usize = 64;

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn method_not_allowed(allow: &str) -> Response {
    Response::empty(StatusCode::MethodNotAllowed).header("Allow", allow)
}

pub struct Router<'a> {
    store: &'a KvStore,
}

impl<'a> Router<'a> {
    pub fn new(store: &'a KvStore) -> Self {
        Self { store }
    }

    pub fn handle(&self, request: Request) -> Response {
        match request.target.as_str() {
            "/health" if request.method == "GET" => Response::text(StatusCode::Ok, "ok"),
            "/kv" if request.method == "GET" => self.list_keys(),
            "/health" | "/kv" => method_not_allowed("GET"),
            path => match path.strip_prefix(KV_PREFIX) {
                Some(key) if is_valid_key(key) => {
                    self.handle_key(&request.method, key, request.body)
                }
                Some(_) => Response::empty(StatusCode::BadRequest),
                None => Response::empty(StatusCode::NotFound),
            },
        }
    }

    fn handle_key(&self, method: &str, key: &str, body: Vec<u8>) -> Response {
        match method {
            "GET" => match self.store.get(key) {
                Some(value) => Response::with_body(
                    StatusCode::Ok,
                    Body::Shared(value),
                    "application/octet-stream",
                ),
                None => Response::empty(StatusCode::NotFound),
            },
            "PUT" => Response::empty(if self.store.put(key, body) {
                StatusCode::Created
            } else {
                StatusCode::Ok
            }),
            "DELETE" => Response::empty(if self.store.remove(key) {
                StatusCode::NoContent
            } else {
                StatusCode::NotFound
            }),
            _ => method_not_allowed("GET, PUT, DELETE"),
        }
    }

    fn list_keys(&self) -> Response {
        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
        let keys = self.store.keys();
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
        Response::with_body(
            StatusCode::Ok,
            Body::Owned(json.into_bytes()),
            "application/json",
        )
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
        }
    }

    #[test]
    fn routes() {
        let store = KvStore::new();
        let router = Router::new(&store);
        let status = |m: &str, t: &str, b: &[u8]| router.handle(req(m, t, b)).status;

        assert_eq!(status("GET", "/health", b""), StatusCode::Ok);
        assert_eq!(status("POST", "/health", b""), StatusCode::MethodNotAllowed);
        assert_eq!(status("PUT", "/kv/a", b"x"), StatusCode::Created);
        assert_eq!(status("PUT", "/kv/a", b"y"), StatusCode::Ok);
        assert_eq!(status("PATCH", "/kv/a", b""), StatusCode::MethodNotAllowed);
        assert_eq!(status("GET", "/kv/", b""), StatusCode::BadRequest);
        assert_eq!(status("GET", "/kv/a/b", b""), StatusCode::BadRequest);
        assert_eq!(
            status("GET", &format!("/kv/{}", "a".repeat(65)), b""),
            StatusCode::BadRequest
        );
        assert_eq!(status("GET", "/nope", b""), StatusCode::NotFound);
        assert_eq!(status("DELETE", "/kv/a", b""), StatusCode::NoContent);
        assert_eq!(status("DELETE", "/kv/a", b""), StatusCode::NotFound);
    }
}
