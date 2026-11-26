//! Request routing and the key-value API.

use bytes::Bytes;

use crate::http::{Request, Response, Status};
use crate::store::Store;

const MAX_KEY_LEN: usize = 64;

#[derive(Debug, Default)]
pub struct App {
    store: Store,
}

impl App {
    pub fn new(store: Store) -> Self {
        Self { store }
    }

    pub fn handle(&self, req: Request) -> Response {
        match req.path.as_str() {
            "/health" => match req.method.as_str() {
                "GET" => Response::with_body(Status::Ok, "text/plain; charset=utf-8", "ok"),
                _ => method_not_allowed("GET"),
            },
            "/kv" => match req.method.as_str() {
                "GET" => self.list_keys(),
                _ => method_not_allowed("GET"),
            },
            path => match path.strip_prefix("/kv/") {
                Some(key) if is_valid_key(key) => self.handle_key(&req.method, key, req.body),
                Some(_) => Response::empty(Status::BadRequest),
                None => Response::empty(Status::NotFound),
            },
        }
    }

    fn list_keys(&self) -> Response {
        let body =
            serde_json::to_vec(&self.store.keys()).expect("a list of strings always serializes");
        Response::with_body(Status::Ok, "application/json", body)
    }

    fn handle_key(&self, method: &str, key: &str, body: Bytes) -> Response {
        match method {
            "GET" => match self.store.get(key) {
                Some(value) => Response::with_body(Status::Ok, "application/octet-stream", value),
                None => Response::empty(Status::NotFound),
            },
            "PUT" => {
                let created = self.store.put(key, body);
                Response::empty(if created { Status::Created } else { Status::Ok })
            }
            "DELETE" => {
                if self.store.delete(key) {
                    Response::empty(Status::NoContent)
                } else {
                    Response::empty(Status::NotFound)
                }
            }
            _ => method_not_allowed("GET, PUT, DELETE"),
        }
    }
}

/// A key matches `[A-Za-z0-9_-]{1,64}`.
fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn method_not_allowed(allow: &str) -> Response {
    Response::empty(Status::MethodNotAllowed).header("Allow", allow)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(app: &App, method: &str, path: &str, body: &'static [u8]) -> Response {
        app.handle(Request {
            method: method.into(),
            path: path.into(),
            body: Bytes::from_static(body),
        })
    }

    #[test]
    fn crud_and_listing() {
        let app = App::default();
        assert_eq!(call(&app, "PUT", "/kv/b", b"2").status, Status::Created);
        assert_eq!(call(&app, "PUT", "/kv/a", b"1").status, Status::Created);
        assert_eq!(call(&app, "PUT", "/kv/a", b"x").status, Status::Ok);
        assert_eq!(&call(&app, "GET", "/kv/a", b"").body[..], b"x");
        assert_eq!(&call(&app, "GET", "/kv", b"").body[..], br#"["a","b"]"#);
        assert_eq!(call(&app, "DELETE", "/kv/a", b"").status, Status::NoContent);
        assert_eq!(call(&app, "DELETE", "/kv/a", b"").status, Status::NotFound);
        assert_eq!(call(&app, "GET", "/kv/a", b"").status, Status::NotFound);
    }

    #[test]
    fn errors() {
        let app = App::default();
        let long = format!("/kv/{}", "k".repeat(65));
        for path in ["/kv/", "/kv/a/b", "/kv/a.b", "/kv/é", long.as_str()] {
            assert_eq!(
                call(&app, "GET", path, b"").status,
                Status::BadRequest,
                "{path}"
            );
        }
        assert_eq!(
            call(&app, "GET", &format!("/kv/{}", "k".repeat(64)), b"").status,
            Status::NotFound
        );
        assert_eq!(call(&app, "GET", "/nope", b"").status, Status::NotFound);
        assert_eq!(call(&app, "GET", "/kv/", b"").status, Status::BadRequest);
        assert_eq!(
            call(&app, "POST", "/health", b"").status,
            Status::MethodNotAllowed
        );
        assert_eq!(
            call(&app, "PUT", "/kv", b"").status,
            Status::MethodNotAllowed
        );
        assert_eq!(
            call(&app, "PATCH", "/kv/a", b"").status,
            Status::MethodNotAllowed
        );
    }
}
