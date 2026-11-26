//! `GET /health`, `POST /notes`, `GET /notes/{id}`, and the routing fallbacks.

mod common;

use axum::http::{Method, StatusCode};
use serde_json::json;

use common::{TestApp, assert_bad_request};

#[tokio::test]
async fn health() {
    let app = TestApp::new();
    let response = app.get("/health").await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.text(), "ok");
}

#[tokio::test]
async fn create_and_get() {
    let app = TestApp::new();

    let first = app.post("/notes", r#"{"title":"first"}"#).await;
    assert_eq!(first.status, StatusCode::CREATED);
    assert_eq!(first.content_type.as_deref(), Some("application/json"));
    assert_eq!(
        first.json(),
        json!({"id": 1, "title": "first", "body": "", "tags": []})
    );

    let second = app
        .post(
            "/notes",
            r#"{"title":"  second  ","body":"some text","tags":["work","b-2","work"]}"#,
        )
        .await;
    assert_eq!(second.status, StatusCode::CREATED);
    let expected =
        json!({"id": 2, "title": "second", "body": "some text", "tags": ["b-2", "work"]});
    assert_eq!(second.json(), expected);

    let fetched = app.get("/notes/2").await;
    assert_eq!(fetched.status, StatusCode::OK);
    assert_eq!(fetched.json(), expected);
}

#[tokio::test]
async fn create_rejects_invalid_bodies() {
    let app = TestApp::new();
    for body in [
        r#"{"title": "#,
        "",
        "[]",
        "{}",
        r#"{"title":"   "}"#,
        r#"{"title":"x","tags":["Bad"]}"#,
        r#"{"title":"x","tags":"x"}"#,
        r#"{"title":"x","body":3}"#,
    ] {
        assert_bad_request(&app.post("/notes", body).await);
    }
    // Nothing was stored, so the next id is still 1.
    assert_eq!(
        app.post("/notes", r#"{"title":"ok"}"#).await.json()["id"],
        1
    );
}

#[tokio::test]
async fn unknown_paths_and_ids_are_not_found() {
    let app = TestApp::new();
    for uri in [
        "/nope",
        "/notes/abc",
        "/notes/0",
        "/notes/-1",
        "/notes/7",
        "/notes/1/x",
    ] {
        let response = app.get(uri).await;
        assert_eq!(response.status, StatusCode::NOT_FOUND, "{uri}");
        assert!(response.json()["error"].is_string());
    }
}

#[tokio::test]
async fn unsupported_methods_are_not_allowed() {
    let app = TestApp::new();
    for (method, uri) in [
        (Method::PATCH, "/notes"),
        (Method::POST, "/health"),
        (Method::POST, "/notes/1"),
    ] {
        let response = app.request(method.clone(), uri, None).await;
        assert_eq!(
            response.status,
            StatusCode::METHOD_NOT_ALLOWED,
            "{method} {uri}"
        );
        assert!(response.json()["error"].is_string());
    }
}

#[tokio::test]
async fn data_survives_restart() {
    let app = TestApp::new();
    app.post("/notes", r#"{"title":"kept","tags":["a"]}"#).await;

    let app = app.restart();
    assert_eq!(
        app.get("/notes/1").await.json(),
        json!({"id": 1, "title": "kept", "body": "", "tags": ["a"]})
    );
    assert_eq!(
        app.post("/notes", r#"{"title":"next"}"#).await.json()["id"],
        2
    );
}

#[tokio::test]
async fn concurrent_creates_get_distinct_ids() {
    let app = std::sync::Arc::new(TestApp::new());
    let tasks: Vec<_> = (0..32)
        .map(|i| {
            let app = app.clone();
            tokio::spawn(async move {
                app.post("/notes", &format!(r#"{{"title":"n{i}"}}"#))
                    .await
                    .json()["id"]
                    .as_i64()
                    .unwrap()
            })
        })
        .collect();
    let mut ids = Vec::new();
    for task in tasks {
        ids.push(task.await.unwrap());
    }
    ids.sort_unstable();
    assert_eq!(ids, (1..=32).collect::<Vec<_>>());
}
