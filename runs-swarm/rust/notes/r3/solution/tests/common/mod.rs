//! Helpers for driving the router in-process.

#![allow(dead_code)]

use axum::Router;
use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use tower::ServiceExt;

/// The application over a fresh database, deleted on drop.
pub struct TestApp {
    router: Router,
    _dir: tempfile::TempDir,
}

pub struct TestResponse {
    pub status: StatusCode,
    pub content_type: Option<String>,
    pub body: Vec<u8>,
}

impl TestResponse {
    pub fn json(&self) -> Value {
        serde_json::from_slice(&self.body).expect("response body is JSON")
    }

    pub fn text(&self) -> &str {
        std::str::from_utf8(&self.body).expect("response body is UTF-8")
    }
}

impl TestApp {
    pub fn new() -> Self {
        let dir = tempfile::tempdir().expect("create temp dir");
        let store = notes::Store::open(dir.path().join("notes.db")).expect("open store");
        Self {
            router: notes::router(notes::AppState { store }),
            _dir: dir,
        }
    }

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
}
