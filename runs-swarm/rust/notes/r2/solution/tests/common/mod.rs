//! Helpers shared by the integration tests: an in-process app over a temporary database.
#![allow(dead_code)] // Each test crate uses a different subset.

use axum::Router;
use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use tempfile::TempDir;
use tower::ServiceExt;

use notes::{AppState, Db};

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
                "invalid JSON body {:?}: {err}",
                String::from_utf8_lossy(&self.body)
            )
        })
    }

    pub fn text(&self) -> &str {
        std::str::from_utf8(&self.body).expect("UTF-8 body")
    }
}

impl TestApp {
    pub fn new() -> Self {
        let dir = tempfile::tempdir().expect("create temp dir");
        let router = Self::open(&dir);
        Self { router, dir }
    }

    fn open(dir: &TempDir) -> Router {
        let db = Db::open(dir.path().join("notes.db")).expect("open database");
        notes::router(AppState { db })
    }

    /// Reopens the same database file, as after a server restart.
    pub fn restart(&mut self) {
        self.router = Self::open(&self.dir);
    }

    pub async fn request(&self, method: Method, uri: &str, body: Option<&str>) -> TestResponse {
        let mut request = Request::builder().method(method).uri(uri);
        if body.is_some() {
            request = request.header("content-type", "application/json");
        }
        let request = request
            .body(body.map_or_else(Body::empty, |b| Body::from(b.to_owned())))
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

    /// Creates a note and returns its JSON, asserting success.
    pub async fn create(&self, body: Value) -> Value {
        let response = self.post("/notes", &body.to_string()).await;
        assert_eq!(response.status, StatusCode::CREATED, "{}", response.text());
        response.json()
    }
}
