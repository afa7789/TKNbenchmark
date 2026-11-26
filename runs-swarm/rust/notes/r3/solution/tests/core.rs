mod common;

use axum::http::{Method, StatusCode};
use common::TestApp;
use serde_json::json;

#[tokio::test]
async fn health() {
    let app = TestApp::new();
    let res = app.get("/health").await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(res.text(), "ok");
}

#[tokio::test]
async fn create_and_get() {
    let app = TestApp::new();
    let res = app.post("/notes", r#"{"title":"first"}"#).await;
    assert_eq!(res.status, StatusCode::CREATED);
    assert_eq!(res.content_type.as_deref(), Some("application/json"));
    assert_eq!(
        res.json(),
        json!({"id": 1, "title": "first", "body": "", "tags": []})
    );

    let res = app
        .post(
            "/notes",
            r#"{"title":"  second  ","body":"some text","tags":["work","b-2","work"]}"#,
        )
        .await;
    let second = json!({"id": 2, "title": "second", "body": "some text", "tags": ["b-2", "work"]});
    assert_eq!(res.status, StatusCode::CREATED);
    assert_eq!(res.json(), second);

    let res = app.get("/notes/2").await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(res.json(), second);
}

#[tokio::test]
async fn create_errors_are_json() {
    let app = TestApp::new();
    for body in [
        r#"{"title": "#,
        "[]",
        "{}",
        r#"{"title":"   "}"#,
        r#"{"title":"x","tags":["Bad"]}"#,
    ] {
        let res = app.post("/notes", body).await;
        assert_eq!(res.status, StatusCode::BAD_REQUEST, "{body}");
        assert!(res.json()["error"].is_string(), "{body}");
    }
}

#[tokio::test]
async fn not_found() {
    let app = TestApp::new();
    for uri in [
        "/nope",
        "/notes/abc",
        "/notes/0",
        "/notes/-1",
        "/notes/7",
        "/notes/1/x",
    ] {
        let res = app.get(uri).await;
        assert_eq!(res.status, StatusCode::NOT_FOUND, "{uri}");
        assert!(res.json()["error"].is_string(), "{uri}");
    }
}

#[tokio::test]
async fn method_not_allowed() {
    let app = TestApp::new();
    let res = app.request(Method::DELETE, "/notes", None).await;
    assert_eq!(res.status, StatusCode::METHOD_NOT_ALLOWED);
    assert!(res.json()["error"].is_string());
    let res = app.request(Method::POST, "/health", None).await;
    assert_eq!(res.status, StatusCode::METHOD_NOT_ALLOWED);
}
