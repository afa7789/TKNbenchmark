//! Routing and the in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{Mutex, MutexGuard};

use bytes::Bytes;

use crate::http::{Request, Response, Status};

const KV_PREFIX: &str = "/kv/";
const MAX_KEY_LEN: usize = 64;

/// Whether `key` matches `[A-Za-z0-9_-]{1,64}`.
fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Thread-safe in-memory store. Keys are kept sorted so listing is cheap.
#[derive(Debug, Default)]
pub struct KvStore {
    data: Mutex<BTreeMap<String, Bytes>>,
}

impl KvStore {
    fn lock(&self) -> MutexGuard<'_, BTreeMap<String, Bytes>> {
        // A panic while holding the lock cannot leave the map inconsistent.
        self.data
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Store a value; return `true` if the key was new.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        self.lock().insert(key.to_owned(), value).is_none()
    }

    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.lock().get(key).cloned()
    }

    /// Remove a key; return `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        self.lock().remove(key).is_some()
    }

    /// Every key, sorted ascending.
    pub fn keys(&self) -> Vec<String> {
        self.lock().keys().cloned().collect()
    }
}

/// The request router.
#[derive(Debug, Default)]
pub struct App {
    store: KvStore,
}

impl App {
    pub fn handle(&self, req: Request) -> Response {
        match req.path.as_str() {
            "/health" => match req.method.as_str() {
                "GET" => Response::with_body(Status::Ok, "text/plain", "ok"),
                _ => method_not_allowed("GET"),
            },
            "/kv" => match req.method.as_str() {
                "GET" => Response::with_body(
                    Status::Ok,
                    "application/json",
                    keys_json(&self.store.keys()),
                ),
                _ => method_not_allowed("GET"),
            },
            path => match path.strip_prefix(KV_PREFIX) {
                Some(key) if is_valid_key(key) => self.handle_key(&req.method, key, req.body),
                Some(_) => Response::new(Status::BadRequest),
                None => Response::new(Status::NotFound),
            },
        }
    }

    fn handle_key(&self, method: &str, key: &str, body: Bytes) -> Response {
        match method {
            "GET" => match self.store.get(key) {
                Some(value) => Response::with_body(Status::Ok, "application/octet-stream", value),
                None => Response::new(Status::NotFound),
            },
            "PUT" => {
                let created = self.store.put(key, body);
                Response::new(if created { Status::Created } else { Status::Ok })
            }
            "DELETE" => {
                if self.store.delete(key) {
                    Response::new(Status::NoContent)
                } else {
                    Response::new(Status::NotFound)
                }
            }
            _ => method_not_allowed("GET, PUT, DELETE"),
        }
    }
}

fn method_not_allowed(allow: &str) -> Response {
    Response::new(Status::MethodNotAllowed).header("Allow", allow)
}

/// Encode keys as a compact JSON array. Valid keys never need escaping.
fn keys_json(keys: &[String]) -> String {
    let mut out = String::with_capacity(2 + keys.iter().map(|k| k.len() + 3).sum::<usize>());
    out.push('[');
    for (i, key) in keys.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('"');
        out.push_str(key);
        out.push('"');
    }
    out.push(']');
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn req(method: &str, path: &str, body: &'static [u8]) -> Request {
        Request {
            method: method.into(),
            path: path.into(),
            headers: HashMap::new(),
            body: Bytes::from_static(body),
        }
    }

    fn status(app: &App, method: &str, path: &str) -> u16 {
        app.handle(req(method, path, b"")).status.code()
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
    fn crud_and_listing() {
        let app = App::default();
        assert_eq!(
            app.handle(req("PUT", "/kv/b", b"2")).status,
            Status::Created
        );
        assert_eq!(
            app.handle(req("PUT", "/kv/a", b"1")).status,
            Status::Created
        );
        assert_eq!(app.handle(req("PUT", "/kv/a", b"x")).status, Status::Ok);
        assert_eq!(&app.handle(req("GET", "/kv/a", b"")).body[..], b"x");
        assert_eq!(
            &app.handle(req("GET", "/kv", b"")).body[..],
            br#"["a","b"]"#
        );
        assert_eq!(status(&app, "DELETE", "/kv/a"), 204);
        assert_eq!(status(&app, "DELETE", "/kv/a"), 404);
        assert_eq!(status(&app, "GET", "/kv/a"), 404);
    }

    #[test]
    fn errors() {
        let app = App::default();
        assert_eq!(&app.handle(req("GET", "/kv", b"")).body[..], b"[]");
        assert_eq!(status(&app, "GET", "/nope"), 404);
        assert_eq!(status(&app, "GET", "/kv/"), 400);
        assert_eq!(status(&app, "GET", "/kv/a/b"), 400);
        assert_eq!(status(&app, "PATCH", "/kv/bad.key"), 400);
        assert_eq!(status(&app, "POST", "/health"), 405);
        assert_eq!(status(&app, "DELETE", "/kv"), 405);
        assert_eq!(status(&app, "PATCH", "/kv/a"), 405);
    }
}
