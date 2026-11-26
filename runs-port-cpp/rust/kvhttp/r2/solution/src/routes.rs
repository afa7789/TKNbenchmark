//! The key-value HTTP API.

use crate::http::{Request, Response};
use crate::store::{KvStore, PutResult};

const KV_PREFIX: &str = "/kv/";
const MAX_KEY_LENGTH: usize = 64;

/// Returns true if `key` matches `[A-Za-z0-9_-]{1,64}`.
pub fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LENGTH).contains(&key.len())
        && key
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
}

/// Dispatches a request against the key-value API.
pub fn route(store: &KvStore, request: Request) -> Response {
    match request.target.as_str() {
        "/health" => handle_health(&request),
        "/kv" => handle_list(store, &request),
        path => match path.strip_prefix(KV_PREFIX) {
            Some(key) => {
                let key = key.to_owned();
                handle_key(store, request, key)
            }
            None => not_found(),
        },
    }
}

fn not_found() -> Response {
    Response::text(404, "not found")
}

fn method_not_allowed(allow: &str) -> Response {
    Response::text(405, "Method Not Allowed").with_header("Allow", allow)
}

fn handle_health(request: &Request) -> Response {
    match request.method.as_str() {
        "GET" => Response::text(200, "ok"),
        _ => method_not_allowed("GET"),
    }
}

fn handle_list(store: &KvStore, request: &Request) -> Response {
    if request.method != "GET" {
        return method_not_allowed("GET");
    }
    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
    let quoted: Vec<String> = store
        .keys()
        .iter()
        .map(|key| format!("\"{key}\""))
        .collect();
    let body = format!("[{}]", quoted.join(","));
    Response::new(
        200,
        vec![("Content-Type".into(), "application/json".into())],
        body.into_bytes(),
    )
}

fn handle_key(store: &KvStore, request: Request, key: String) -> Response {
    if !is_valid_key(&key) {
        return Response::text(400, "invalid key");
    }
    match request.method.as_str() {
        "GET" => match store.get(&key) {
            Some(value) => Response::new(
                200,
                vec![("Content-Type".into(), "application/octet-stream".into())],
                value,
            ),
            None => not_found(),
        },
        "PUT" => match store.put(key, request.body) {
            PutResult::Created => Response::empty(201),
            PutResult::Replaced => Response::empty(200),
        },
        "DELETE" => {
            if store.remove(&key) {
                Response::empty(204)
            } else {
                not_found()
            }
        }
        _ => method_not_allowed("GET, PUT, DELETE"),
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
    fn key_validation() {
        assert!(is_valid_key("a-Z_09"));
        assert!(is_valid_key(&"k".repeat(64)));
        assert!(!is_valid_key(&"k".repeat(65)));
        assert!(!is_valid_key(""));
        assert!(!is_valid_key("a/b"));
        assert!(!is_valid_key("a.b"));
    }

    #[test]
    fn routing() {
        let store = KvStore::new();
        assert_eq!(route(&store, req("GET", "/health", b"")).status, 200);
        assert_eq!(route(&store, req("POST", "/health", b"")).status, 405);
        assert_eq!(route(&store, req("GET", "/nope", b"")).status, 404);
        assert_eq!(route(&store, req("GET", "/kv/", b"")).status, 400);
        assert_eq!(route(&store, req("PATCH", "/kv/a", b"")).status, 405);
        assert_eq!(route(&store, req("PUT", "/kv/b", b"x")).status, 201);
        assert_eq!(route(&store, req("PUT", "/kv/a", b"y")).status, 201);
        assert_eq!(route(&store, req("PUT", "/kv/a", b"z")).status, 200);
        assert_eq!(route(&store, req("GET", "/kv/a", b"")).body, b"z");
        assert_eq!(route(&store, req("GET", "/kv", b"")).body, br#"["a","b"]"#);
        assert_eq!(route(&store, req("DELETE", "/kv/a", b"")).status, 204);
        assert_eq!(route(&store, req("DELETE", "/kv/a", b"")).status, 404);
        assert_eq!(route(&store, req("GET", "/kv/a", b"")).status, 404);
    }
}
