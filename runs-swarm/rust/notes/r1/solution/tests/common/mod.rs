//! Helpers for in-process HTTP tests: each [`TestApp`] has its own temporary database.
#![allow(dead_code)]

use axum::Router;
use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use tempfile::TempDir;
use tower::ServiceExt;

use notes::app;
use notes::store::Db;

pub struct TestApp {
    router: Router,
    dir: TempDir,
}

pub struct TestResponse {
    pub status: StatusCode,
    pub content_type: Option<String>,
    pub body: Vec<u8>,
}

impl TestResponse {
    pub fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or_else(|err| {
            panic!(
                "invalid JSON ({err}): {}",
                String::from_utf8_lossy(&self.body)
            )
        })
    }

    pub fn text(&self) -> &str {
        std::str::from_utf8(&self.body).expect("body is not UTF-8")
    }
}

impl TestApp {
    pub fn new() -> Self {
        let dir = tempfile::tempdir().expect("create temp dir");
        let router = app::router(Db::open(dir.path().join("notes.db")).expect("open db"));
        Self { router, dir }
    }

    /// Reopens the same database file, as after a restart.
    pub fn restart(self) -> Self {
        let Self { router, dir } = self;
        drop(router);
        let router = app::router(Db::open(dir.path().join("notes.db")).expect("reopen db"));
        Self { router, dir }
    }

    /// Sends a request; `body` is sent verbatim, without a `Content-Type` header.
    pub async fn request(&self, method: Method, uri: &str, body: Option<&str>) -> TestResponse {
        let body = body.map_or_else(Body::empty, |b| Body::from(b.to_owned()));
        let request = Request::builder()
            .method(method)
            .uri(uri)
            .body(body)
            .unwrap();
        let response = self.router.clone().oneshot(request).await.unwrap();
        let status = response.status();
        let content_type = response
            .headers()
            .get("content-type")
            .map(|v| v.to_str().unwrap().to_owned());
        let body = response
            .into_body()
            .collect()
            .await
            .unwrap()
            .to_bytes()
            .to_vec();
        TestResponse {
            status,
            content_type,
            body,
        }
    }

    pub async fn get(&self, uri: &str) -> TestResponse {
        self.request(Method::GET, uri, None).await
    }

    pub async fn post(&self, uri: &str, body: &str) -> TestResponse {
        self.request(Method::POST, uri, Some(body)).await
    }

    pub async fn put(&self, uri: &str, body: &str) -> TestResponse {
        self.request(Method::PUT, uri, Some(body)).await
    }

    pub async fn delete(&self, uri: &str) -> TestResponse {
        self.request(Method::DELETE, uri, None).await
    }
}

/// Asserts a 400 with a JSON `{"error": "<message>"}` body.
pub fn assert_bad_request(response: &TestResponse) {
    assert_eq!(
        response.status,
        StatusCode::BAD_REQUEST,
        "{}",
        String::from_utf8_lossy(&response.body)
    );
    assert!(response.json()["error"].is_string());
}
